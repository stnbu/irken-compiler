;; -*- Mode: Irken -*-

;; generated by demo/parse/lexgen from parse/meta-lex.sg
;; do not edit.

(define table-g
  (let (
      (t0 (rle (9 1) 2 3 (21 1) 2 (14 1) 4 (10 1) 7 8 (5 1) (26 9) (4 1) 9 1 (26 9) 1 10 (131 1)))
      (t1 (rle (256 1)))
      (t2 (rle (9 1) 2 3 (21 1) 2 (14 1) 4 (208 1)))
      (t3 (rle (9 1) (2 3) (21 1) 3 (223 1)))
      (t4 (rle (47 1) 5 (208 1)))
      (t5 (rle (10 5) 6 (245 5)))
      (t6 (rle (48 1) (10 9) (7 1) (26 9) (4 1) 9 1 (26 9) (133 1)))
        )
     (list->vector (list t0 t1 t2 t3 t4 t5 t1 t1 t1 t6 t1))))

(define finals-g #(
  'not-final
  '%%sink%%
  'WHITESPACE
  'WHITESPACE
  'not-final
  'not-final
  'COMMENT
  'COLON
  'SEMICOLON
  'NAME
  'VBAR
  ))

(define (step-g ch state)
  (%array-ref #f table-g[state] (char->ascii ch)))

(define dfa-g {step=step-g  table=table-g  finals=finals-g})