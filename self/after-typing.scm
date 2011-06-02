;; -*- Mode: Irken -*-

(define (safe-for-let-reg exp names context)
  (and (node-get-flag exp NFLAG-LEAF)
       (< (length names) 5)
       (not (some?
	     (lambda (name)
	       (vars-get-flag context name VFLAG-ESCAPES))
	     names))))

(define (remove-lets-from-fun name formals node context)
  
  (print-string (format "removing lets from " (sym name) "\n"))

  (let ((vars '()))

    (define (walk node)
      (print-string (format "walking node " (int node.id) "\n"))
      (match node.t with
	(node:let syms)
	-> (cond ((safe-for-let-reg node syms context) node) ;; leave this one be
		 (else
		  (set! vars (append vars syms))
		  (let loop ((inits '())
			     (syms syms)
			     (subs node.subs))
		    (match syms subs with
		      () _			-> (node/sequence (append (reverse inits) (map walk subs)))
		      (sym . syms) (sub . subs) -> (loop (list:cons (node/varset sym sub) inits) syms subs)
		      _ _			-> (impossible)
		      ))))
	(node:function name formals) -> (remove-lets-from-fun name formals node context)
	_ -> (begin (set! node.subs (map walk node.subs)) node)
	))

    (let ((subs0 (map walk node.subs)))
      (set! node.subs subs0)
      (set! node.t (node:function name (append formals vars)))
      node)))

;;; urgh, how to remove lets from the top level?

(define (remove-lets node context)
  (define (walk node)
    (match node.t with
      (node:function name formals) -> (remove-lets-from-fun name formals node context)
      _				   -> (begin (set! node.subs (map walk node.subs)) node)
      ))
  (walk node))
