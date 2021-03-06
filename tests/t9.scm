
;; do some allocation in the loop

(datatype bool (:true) (:false))

(define (- a b)
  (%%cexp (int int -> int) "%0-%1" a b))

(define (= a b)
  (%%cexp (int int -> bool) "%0==%1" a b))

(define (zero? x)
  (%%cexp (int -> bool) "%0==0" x))

(let loop ((n 1000000)
	   (z {thing=0 blorb=#f})
	   (y (:blort 12)))
  (if (zero? n)
      z
      (loop (- n 1)
	    {thing=n blorb=#f}
	    (:blort n))))
