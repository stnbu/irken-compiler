;; -*- Mode: Irken -*-

;; XXX move this into lib/parse/

;; assumes the presence of a 'step' function, generated by parse/lexer.py,
;; that looks like this:
;  (define (step ch state)
;;   (char->ascii (string-ref dfa[state] (char->ascii ch))))

(datatype range
  ;; range within a source file
  ;; <line0> <pos0> <line1> <pos1>
  (:t int int int int)
  ;; undefined range
  (:f)
  )

(datatype token
  ;;  <kind> <value> <range>
  (:t symbol string (range))
  )

;; run-length encoding is used by the lexer generator to build
;; DFA tables.
(datatype rle
  (:run int int)
  (:one int)
  )

;; take a list of rle and turn it into an int[256]
(define (rle->vector runs)
  (let ((vec (make-vector 256 0))
        (i 0))
    (for-list run runs
      (match run with
        (rle:one val)
        -> (begin (set! vec[i] val) (set! i (+ i 1)))
        (rle:run n val)
        -> (for-range j n
             (set! vec[i] val)
             (set! i (+ i 1)))
        ))
    vec))

(define (lex dfa producer consumer)
  ;; producer gives us characters
  ;; consumer takes tokens

  (let ((action 'not-final)
	(state 0)
	;; current char's position
	(line 1)
	(pos 1)
	;; previous char's position
	(lline 1)
	(lpos 1)
	;; start of last token
	(tline 1)
	(tpos 1)
	)

    (define (next-char)
      ;; manage line/pos
      (let ((ch (producer)))
	(set! lline line)
	(set! lpos pos)
	(cond ((char=? ch #\newline)
	       (set! line (+ line 1))
	       (set! pos 1))
	      (else
	       (set! pos (+ pos 1))))
	ch))

    (define (final? action)
      (not (eq? action 'not-final)))

    (define (emit tok)
      (consumer (maybe:yes tok)))

    (let loop ((ch (next-char))
	       (last 'not-final)
	       (current (list:nil)))
      (cond ((char=? ch #\eof)
	     (emit (token:t '<$> "<$>" (range:t tline tpos line pos))) #t)
	    (else
	     (set! state (dfa.step ch state))
	     (set! action dfa.finals[state])
	     (cond ((and (not (final? last)) (final? action))
		    ;; we've entered a new final state
		    (loop (next-char) action (list:cons ch current)))
		   ((and (final? last) (not (final? action)))
		    ;; we've left a final state - longest match - emit token
		    (emit (token:t last (list->string (reverse current)) (range:t tline tpos lline lpos)))
		    (set! state 0)
		    (set! tline lline)
		    (set! tpos lpos)
		    (loop ch 'not-final (list:nil)))
		   (else
		    ;; accumulate this character
		    (loop (next-char) action (list:cons ch current)))))))
      ))

(define (make-lex-generator dfa file)

  (define (producer)
    (file/read-char file))

  (make-generator
   (lambda (consumer)
     (lex dfa producer consumer)
     (forever (consumer (maybe:no)))
     )))

