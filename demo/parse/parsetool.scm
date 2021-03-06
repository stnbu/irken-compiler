;; -*- Mode: Irken -*-

(require "lib/basis.scm")
(require "lib/parse/lexer.scm")
(require "lib/parse/parser.scm")

(if (< sys.argc 3)
    (begin (printf "\nParse a file with a given grammar.\n")
           (printf " the output is an s-expression parse tree.\n\n")
           (printf "Usage: " sys.argv[0] " <grammar.sg> <input-file>\n\n")
           (printf "  example: $ " sys.argv[0] " bcpl.sg sample.bcpl\n")
           (printf "           $ " sys.argv[0] " meta.sg g.g\n\n")
           (printf "     <grammar>: an s-expression combined lexicon+grammar parser.\n")
           (printf "  <input-file>: a source file written in the target language.\n"))
    (let ((gpath sys.argv[1])
          (gfile (file/open-read gpath))
          ;; read the parser spec as an s-expression
          (exp (reader gpath (lambda () (file/read-char gfile))))
          ((lexicon filter grammar start) (sexp->parser exp))
          ;; convert the lexicon to a dfa
          (dfa0 (lexicon->dfa lexicon))
          ((labels dfa1) dfa0)
          ;; build a lexer from the dfa
          (lexer (dfa->lexer dfa0))
          ;; create a stream of tokens
          (spath sys.argv[2])
          (sfile (file/open-read spath))
          (gen0 (file-char-generator sfile))
          (gen1 (make-lex-generator lexer gen0))
          ;; pass the stream through the token filter
          (gen2 (filter-gen filter gen1))
          ;; build it into a parse tree.
          (parse (earley grammar (prod:nt start) gen2))
          )
      ;;(print-dfa dfa1)
      ;; pretty-print the parse tree
      (pp (parse->sexp parse) 40)
      ))
