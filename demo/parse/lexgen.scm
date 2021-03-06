;; -*- Mode: Irken -*-

(require "lib/basis.scm")
(require "lib/dfa/lexicon.scm")
(require "lib/dfa/emit.scm")

(if (< sys.argc 3)
    (begin (printf "\nGenerate a lexer dfa (in Irken) to stdout.\n\n")
           (printf "Usage: " sys.argv[0] " <lexicon.sg> <basename>\n")
           (printf "    example: $ " sys.argv[0] " bcpl.sg bcpl > lexbcpl.scm\n")
           (printf "  <basename> is used to uniquely name the top-level Irken objects,\n")
           (printf "    for example table-bcpl, step-bcpl and dfa-bcpl.\n"))
    (let ((lexpath sys.argv[1])
          (base (string->symbol sys.argv[2]))
          (lexfile (file/open-read lexpath))
          ;; read the parser spec as an s-expression
          (exp (reader lexpath (lambda () (file/read-char lexfile))))
          (lexicon (sexp->lexicon (car exp)))
          ;; convert the lexicon to a dfa
          (dfa0 (lexicon->dfa lexicon))
          ((labels dfa1) dfa0)
          ;; build a lexer from the dfa
          (lexer (dfa->lexer dfa0)))
      (printf ";; -*- Mode: Irken -*-\n\n")
      (printf ";; generated by " sys.argv[0] " from " sys.argv[1] "\n")
      (printf ";; do not edit.\n\n")
      (emit-irken-lexer lexer base)
      ))
