;; -*- Mode: Irken -*-

(include "lib/core.scm")

(define (gweep)
  (let ((x (%getcc #f)))
    88))

(define (thing x)
  (let ((y (+ x 1)))
    (+ y 1)
    (let ((y (+ x 1)))
      (+ y 1)
      (let ((y (+ x 1)))
	(+ y 1)
	(let ((y (+ x 1)))
	  (+ y 1)
	  (let ((y (+ x 1)))
	    (if (= x 0)
		99
		(begin
		  (gweep)
		  (printn "howdy")
		  (thing (- x 1))))))))))

(thing 10)

	    
    
    