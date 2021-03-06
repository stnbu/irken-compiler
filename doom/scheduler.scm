;; -*- Mode: Irken -*-

(require "doom/kqueue.scm")

;; XXX we will need a priority queue.

;; for each EVFILT, we have separate map of ident=>continuation

(define (make-poller)
  { kqfd	= (kqueue/kqueue)
    runnable	= (queue/make)
    nwait	= 0 ;; how many events are waiting?
    filters	= (make-vector EVFILT_SYSCOUNT (tree/empty))
    ievents	= (make-changelist 1000)
    oevents	= (make-changelist 1000)
    })

(define the-poller (make-poller))

;; store the thread-id and current exc handler along with the continuation.
(define (poller/enqueue k)
  (queue/add! the-poller.runnable (:tuple *thread-id* *the-exception-handler* k)))

(define (poller/enqueue* thread-id exc-handler k)
  (queue/add! the-poller.runnable (:tuple thread-id exc-handler k)))

(define (protect thunk thread-id)
  ;; (printf "starting thread " (int thread-id) "\n")
  (try
   (begin
     (set! *thread-id* thread-id)
     (thunk))
   except
   ;; XXX something forbids us from making a wildcard handler without
   ;;     handling a 'real' exception.  probably the try/except macro?
   (:OSError n)
   -> (printf "OSError " (int n) " in thread.\n")
   anything
   -> (begin
        (printf "unhandled exception in thread: " (int thread-id) "\n")
        (print-exception anything))
   ))

(define next-thread-id
  (let ((thread-counter 1))
    (lambda ()
      (let ((val thread-counter))
        (inc! thread-counter)
        val))))

(define *thread-id* 0)

(defmacro debugf
  (debugf x ...)
  -> (printf (bold "[" (int *thread-id*) "]") x ...)
  )

;; TODO: since this code is using getcc/putcc directly, it's possible
;; that it's not type-safe around coro switch boundaries. look into
;; this.

(define (poller/fork thunk)
  (poller/enqueue (getcc))
  (protect thunk (next-thread-id))
  (poller/dispatch))

(define (poller/yield)
  (poller/enqueue (getcc))
  (poller/dispatch))

(define (poller/dispatch)
  (match (queue/pop! the-poller.runnable) with
    (maybe:yes (:tuple thread-id eh k))
    -> (begin
         (set! *the-exception-handler* eh)
         (set! *thread-id* thread-id)
         (putcc k #u))
    (maybe:no)
    -> (poller/wait-and-schedule)))

;; these funs know that EVFILT values are consecutive small negative ints

;; here's a question: is this an abuse of macros?  Does it make the code
;;   harder or easier to read?  I think this is related to 'setf' in CL -
;;   since the target of set! can't be a funcall.
(defmacro kfilt (kfilt f) -> the-poller.filters[(- f)])

(define (poller/lookup-event ident filter)
  (tree/member (kfilt filter) int-cmp ident))

(define (poller/add-event ident filter k)
  (inc! the-poller.nwait)
  (tree/insert! (kfilt filter)
                int-cmp ident
                (:tuple *thread-id* *the-exception-handler* k)))

(define (poller/delete-event ident filter)
  (tree/delete! (kfilt filter) int-cmp ident)
  (dec! the-poller.nwait))

;; put the current thread to sleep while waiting for the kevent (ident, filter).
(define (poller/wait-for ident filter)
  (let ((k (getcc)))
    (match (poller/lookup-event ident filter) with
      (maybe:no)
      -> (begin
	   (add-kevent the-poller.ievents ident filter EV_ADDONE)
	   (poller/add-event ident filter k)
	   (poller/dispatch)
	   #u
	   )
      (maybe:yes _) -> (raise (:PollerEventAlreadyPresent ident filter))
      )))

(define (poller/wait-for-read fd)
  (poller/wait-for fd EVFILT_READ))

(define (poller/wait-for-write fd)
  (poller/wait-for fd EVFILT_WRITE))

(define poller/enqueue-waiting-thread
  (:kev ident filter)
  -> (match (poller/lookup-event ident filter) with
       (maybe:yes (:tuple thread-id exc-handler k))
       -> (begin
            (poller/delete-event ident filter)
            (poller/enqueue* thread-id exc-handler k))
       (maybe:no)
       -> (begin
            (printf "poller: no such event: " (int ident) " " (int filter) "\n")
            (printf " keys for that filter: " (join int->string " " (tree/keys (kfilt filter))) "\n")
            (raise (:PollerNoSuchEvent ident filter)))
       ))

(define (poller/wait-and-schedule)
  ;; all the runnable threads have done their bit, now throw it to kevent().
  (if (= the-poller.nwait 0)
      (printf "no events, will wait forever!\n"))
  (let ((n (syscall (kevent the-poller.kqfd the-poller.ievents the-poller.oevents))))
    (set! the-poller.ievents.index 0)
    (for-range i n
      (poller/enqueue-waiting-thread
       (get-kevent the-poller.oevents i)))
    (poller/dispatch)
    ))

