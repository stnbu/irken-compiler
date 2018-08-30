;; -*- Mode: Irken -*-

(include "lib/basis.scm")
(include "lib/map.scm")
(include "lib/parse/lexer.scm")
(include "lib/parse/earley.scm")

(define (TOK k v)
  {kind=k val=v range=(range:f)}
  )

;; grammar is a mapping from prod -> (list (list prod))
(let ((E (prod:nt 'E))
      (T (prod:nt 'T))
      (P (prod:nt 'P))
      (add (prod:t '+))
      (mul (prod:t '*))
      (ident (prod:t 'ident))
      (g (alist/make
          ('E (list (list E add T) (list T)))
          ('T (list (list T mul P) (list P)))
          ('P (list (list ident))))))
  (let ((toks (list (TOK 'ident "a")
                    (TOK '*     "*")
                    (TOK 'ident "b")
                    (TOK '+     "+")
                    (TOK 'ident "c")
                    (TOK '*     "*")
                    (TOK 'ident "d")
                    (TOK '+     "+")
                    (TOK 'ident "e")
                    (TOK '+     "+")
                    (TOK 'ident "f")
                    (TOK 'eof   "eof")
                    ))
        (tree (earley g E (list-generator toks))))
    (printf (parse-repr tree) "\n")
    (pp (parse->sexp tree) 50)
    ))