;; -*- Mode: Irken -*-

(require "self/transform.scm")
(require "self/typing.scm")

(datatype literal
  (:string string)
  (:int int)
  (:char char)
  (:bool bool)
  (:undef)
  (:symbol symbol)
  (:cons symbol symbol (list literal))
  (:vector (list literal))
  (:record int (list litfield))
  (:sexp sexp)
  )

(datatype litfield
  (:t symbol literal)
  )

;; node type holds metadata related to the node,
;;  but sub-nodes are held with the record.
(datatype node
  (:varref symbol)
  (:varset symbol)
  (:literal literal)
  (:cexp (list type) type string) ;; generic-tvars type template
  (:ffi (list type) type symbol)  ;; generic-tvars type name
  (:nvcase symbol (list symbol) (list int))  ;; datatype alts arities
  (:sequence)
  (:if)
  (:function symbol (list symbol)) ;; name formals
  (:call)
  (:let (list symbol))
  (:fix (list symbol))
  (:subst symbol symbol)
  (:primapp symbol sexp) ;; name params
  ;; XXX there are several 'fake prims' like %fatbar that arguably
  ;;   should be their own node types.
  )

;; to avoid recursive types, we wrap the node record in a datatype.
(datatype noderec
  (:t {
       t=node		   ;; node kind
       subs=(list noderec) ;; node children
       size=int		   ;; size (including children)
       id=int		   ;; unique id
       type=type	   ;; solved/assigned type
       flags=int	   ;; bit flags (recursive, leaf, etc...)
       })
  )

;; --- accessors ---
(define noderec->rec
  (noderec:t n) -> n)

(define noderec->t
  (noderec:t n) -> n.t)

(define noderec->subs
  (noderec:t n) -> n.subs)

(define noderec->size
  (noderec:t n) -> n.size)

(define noderec->id
  (noderec:t n) -> n.id)

(define noderec->type
  (noderec:t n) -> n.type)

(define noderec->flags
  (noderec:t n) -> n.flags)

(define set-node-subs!
  (noderec:t nr) s -> (set! nr.subs s))

(define set-node-size!
  (noderec:t nr) s -> (set! nr.size s))

(define set-node-type!
  (noderec:t nr) t -> (set! nr.type t))

(define set-node-flags!
  (noderec:t nr) f -> (set! nr.flags f))

(define set-node-t!
  (noderec:t nr) t -> (set! nr.t t))

;; --- accessors ---

(define node-counter (make-counter 0))

;; given a list of nodes, add up their sizes (+1)
(define (sum-size l)
  (fold (lambda (n acc) (+ (noderec->size n) acc)) 1 l))

(define no-type (pred '? '()))

(define no-type?
  (type:pred '? () _) -> #t
  _ -> #f
  )

;; a cleaner way to do this might be with an alist? (makes sense if
;;   most flags are clear most of the time?)
;; flags
(define (node-get-flag node i)
  (bit-get (noderec->flags node) i))

(define (node-set-flag! node i)
  (set-node-flags! node (bit-set (noderec->flags node) i)))

;; defined node flags
(define NFLAG-RECURSIVE 0)
(define NFLAG-ESCAPES   1)
(define NFLAG-LEAF      2)
(define NFLAG-TAIL      3)
(define NFLAG-NFLAGS    4)

;;(typealias rnode
;;   {t=node subs=(list rnode) size=int id=int type=type flags=int})

(define (make-node t subs)
  (noderec:t {t=t subs=subs size=(sum-size subs) id=(node-counter.inc) type=no-type flags=0})
  )

(define (node-copy node0)
  (match node0 with
    (noderec:t {t=(node:literal _) ...}) -> node0 ;; don't copy literals
    (noderec:t nr)
    -> (noderec:t {t=nr.t subs=nr.subs size=nr.size id=(node-counter.inc) type=nr.type flags=nr.flags})
    ))

(define (node/varref name)
  (make-node (node:varref name) '()))

(define (node/varset name val)
  (make-node (node:varset name) (list val)))

(define varref->name
  (node:varref name) -> name
  _ -> (error "varref->name"))

(define (node/literal lit)
  (make-node (node:literal lit) '()))

(define (node/cexp gens type template args)
  (make-node (node:cexp gens type template) args))

(define (node/ffi gens type name args)
  (make-node (node:ffi gens type name) args))

(define (node/sequence subs)
  (make-node (node:sequence) subs))

(define (node/if test then else)
  (let ((nodes (list test then else)))
    (make-node (node:if) nodes)))

(define (node/function name formals type body)
  (let ((node (make-node (node:function name formals) (list body))))
    (match type with
      (sexp:bool #f) -> node
      _ -> (begin (set-node-type! node (parse-type type))
		  node))))

(define function?
  (noderec:t node)
  -> (match node.t with
       (node:function _ _ ) -> #t
       _ -> #f))

(define function->name
  (noderec:t node)
  -> (match node.t with
       (node:function name _) -> name
       _ -> (error "function->name")))

(define (node/call rator rands)
  (let ((subs (list:cons rator rands)))
    (make-node (node:call) subs)))

(define (node/fix names inits body)
  (let ((subs (append inits (list body))))
    (make-node (node:fix names) subs)))

(define (node/let names inits body)
  (let ((subs (append inits (list body))))
    (make-node (node:let names) subs)))

(define (node/nvcase dt tags arities value alts else)
  (let ((subs (list:cons value (list:cons else alts))))
    (make-node (node:nvcase dt tags arities) subs)))

(define (node/subst from to body)
  (make-node (node:subst from to) (list body)))

(define (node/primapp name params args)
  (make-node (node:primapp name params) args))

(define (unpack-fix subs)
  ;; unpack (init0 init1 ... body) for fix and let.
  (let ((rsubs (reverse subs)))
    (match rsubs with
      (body . rinits) -> (:fixsubs body (reverse rinits))
      _ -> (error "unpack-fix: no body?"))))

(define literal->string
  (literal:string s)	 -> (format (string s))
  (literal:symbol s)     -> (format (sym s))
  (literal:int n)	 -> (format (int n))
  (literal:char ch)	 -> (format (repr-char ch))
  (literal:bool b)       -> (if b "#t" "#f")
  (literal:undef)	 -> (format "#u")
  (literal:cons dt v ()) -> (format "(" (sym dt) ":" (sym v) ")")
  (literal:cons dt v l)	 -> (format "(" (sym dt) ":" (sym v) " " (join literal->string " " l) ")")
  (literal:vector l)     -> (format "#(" (join literal->string " " l) ")")
  (literal:record tag fl)-> (format "{" (join litfield->string " " fl) "}")
  (literal:sexp s)       -> (repr s)
  )

(define litfield->string
  (litfield:t name lit)
  -> (format (sym name) "=" (literal->string lit)))

(define (flags-repr n)
  (let loop ((bits '())
	     (n n))
    (cond ((= n 0) (list->string bits))
	  ((= (logand n 1) 1)
	   (loop (list:cons #\1 bits) (>> n 1)))
	  (else
	   (loop (list:cons #\0 bits) (>> n 1))))))

(define indent1
  0 -> #t
  n -> (begin (print-string " ") (indent (- n 1))))

(define format-node-type
  (node:varref name)             -> (format "varref " (sym name))
  (node:varset name)             -> (format "varset " (sym name))
  (node:literal lit)             -> (format "literal " (literal->string lit))
  (node:cexp gens type template) -> (format "cexp " (type-repr type) " " template)
  (node:ffi gens type name)      -> (format "ffi " (type-repr type) " " (sym name))
  (node:sequence)                -> (format "sequence")
  (node:if)                      -> (format "conditional")
  (node:call)                    -> (format "call")
  (node:function name formals)   -> (format "function " (sym name) " (" (join symbol->string " " formals) ") ")
  (node:fix formals)             -> (format "fix (" (join symbol->string " " formals) ") ")
  (node:subst from to)           -> (format "subst " (sym from) "->" (sym to))
  (node:primapp name params)     -> (format "primapp " (sym name) " " (repr params))
  (node:let formals)             -> (format "let (" (join symbol->string " " formals) ")")
  (node:nvcase dt tags arities)  -> (format "nvcase " (sym dt)
                                            "(" (join symbol->string " " tags) ")"
                                            "(" (join int->string " " arities) ")")
  )

(define format-node
  (noderec:t n) d
  -> (format (lpad 6 (int n.id))
	     (lpad 5 (int n.size))
	     (lpad (+ 2 NFLAG-NFLAGS) (flags-repr n.flags) " ")
	     (repeat d "  ")
	     (format-node-type n.t)
	     " : " (type-repr (apply-subst n.type))
	     ))

(define (noderec->sexp node)
  (let ((subs (map noderec->sexp (noderec->subs node))))
    (match (noderec->t node) with
      (node:varref name)             -> (sexp (sym name))
      (node:varset name)             -> (sexp (sym 'set!) (first subs) (second subs))
      (node:literal lit)             -> (sexp (string (literal->string lit)))
      (node:cexp gens type template) -> (sexp (string (type-repr type)) (string template) (list subs))
      (node:ffi gens type name)      -> (sexp (sym 'ffi) (string (type-repr type)) (sym name) (list subs))
      (node:sequence)                -> (sexp1 'begin subs)
      (node:if)                      -> (sexp1 'if subs)
      (node:call)                    -> (sexp1 'call subs)
      (node:function name formals)   -> (sexp (sym 'fun) (sym name) (list (map sexp:symbol formals)) (list subs))
      (node:fix formals)             -> (sexp (sym 'fix) (list (map sexp:symbol formals)) (list subs))
      (node:subst from to)           -> (sexp (sym 'subst) (sym from) (sym to) (list subs))
      (node:primapp name params)     -> (sexp (sym 'primapp) (sym name) params (list subs))
      (node:let formals)             -> (sexp (sym 'let) (list (map sexp:symbol formals)) (list subs))
      (node:nvcase dt tags arities)  -> (sexp (sym 'nvcase) (sym dt) (list (map sexp:symbol tags))
                                              (list (map sexp:int arities))
                                              (list subs))
      )))

(define (walk-node-tree p n d)
  (p n d)
  (for-list sub (noderec->subs n)
    (walk-node-tree p sub (+ d 1)))
  )

(define (make-node-generator n)
  (make-generator
   (lambda (consumer)
     (walk-node-tree
      (lambda (n d)
	(consumer (maybe:yes (:tuple n d))))
      n 0)
     (forever (consumer (maybe:no)))
     )))

(define (pp-node root)
  (let ((ng (make-node-generator root)))
    (let loop ()
      (match (ng) with
	(maybe:yes (:tuple n d))
	-> (begin (print-string (format-node n d)) (newline)
                  (loop))
        (maybe:no)
        -> #u))))

(define (highlight s)
  (format "\x1b[1;1m" s "\x1b[0m")
  )

;; render the node tree, looking for a window of <count> lines
;;   around the node with <id>.  for printing errors.
(define (get-node-context root id count)
  (let ((context (make-vector count ""))
        (collected 0) ;; #lines collected after <id>
        (ng (make-node-generator root)))
    (define (result i)
      (let ((r (list:nil)))
	(for-range
	    j count
	    (push! r context[(remainder (+ i j) count)]))
	(reverse r)))
    (let loop ((i 0))
      (match (ng) with
        (maybe:yes (:tuple n d))
        -> (begin (set! context[i] (format-node n d))
                  ;; state machine
		  (if (= (noderec->id n) id)
		      (set! context[i] (highlight context[i])))
                  (cond ((= collected (/ count 2)) (result (+ i 1)))
			((or (> collected 0) (= (noderec->id n) id))
			 (set! collected (+ collected 1))
			 (loop (remainder (+ i 1) count)))
			(else
			 (loop (remainder (+ i 1) count)))))
        (maybe:no) -> (result i)
        ))))

(define (get-node-funpath root id)
  (let/cc return
    (let recur ((node root)
                (funpath '()))
      (let ((id0 (noderec->id node)))
        (match (noderec->t node) with
          (node:function name formals)
          -> (push! funpath name)
          _ -> #u)
        (if (= id0 id)
            (return (reverse funpath))
            (for-list sub (noderec->subs node)
              (recur sub funpath)))
        '()
        ))
    ))

;; --- can-haz-literal? ---
;; this scans an s-expression to determine if it can be represented
;;   as a literal or not.

(define can-haz-literal-fields?
  () -> #t
  ((field:t sym val) . rest)
  -> (and (can-haz-literal? val)
          (can-haz-literal-fields? rest)))

(define can-haz-literal?
  (sexp:string s)  -> #t
  (sexp:int n)     -> #t
  (sexp:char c)    -> #t
  (sexp:bool b)    -> #t
  (sexp:undef)     -> #t
  (sexp:symbol s)  -> #f ;; i.e., varref
  (sexp:list ((sexp:symbol 'quote) . _)) -> #t
  (sexp:list ((sexp:cons _ _) . args))   -> (every? can-haz-literal? args)
  (sexp:list l)                          -> (every? can-haz-literal? l)
  (sexp:vector l)                        -> (every? can-haz-literal? l)
  ;; note: we cannot have embedded record literals (because mutability)
  ;;(sexp:record fields)                   -> (can-haz-literal-fields? fields)
  _                                      -> #f
  )

(define (sexp->node sexp)

  (define build-list-literal
    ((sexp:cons dt alt) . args) -> (literal:cons dt alt (map build-literal args))
    ((sexp:symbol 'quote) arg)  -> (build-literal arg)
    (hd . tl)                   -> (literal:cons 'list 'cons (list (build-literal hd) (build-list-literal tl)))
    ()                          -> (literal:cons 'list 'nil '())
    )

  (define build-field
    (field:t name val)
    -> (litfield:t name (build-literal val))
    )

  (define (build-record-literal fields)
    (let ((fields0 (sort field<? fields))
          (sig (map (lambda (x) (match x with (field:t name _) -> name)) fields0))
          (tag (cmap/add the-context.records sig)))
      (for-each (lambda (label) (cmap/add the-context.labels label)) sig)
      (cmap/add the-context.records sig)
      (literal:record tag (map build-field fields0))))

  (define build-literal
    (sexp:string s)  -> (literal:string s)
    (sexp:int n)     -> (literal:int n)
    (sexp:char c)    -> (literal:char c)
    (sexp:bool b)    -> (literal:bool b)
    (sexp:undef)     -> (literal:undef)
    (sexp:symbol s)  -> (literal:symbol s)
    (sexp:list l)    -> (build-list-literal l)
    (sexp:vector l)  -> (literal:vector (map build-literal l))
    (sexp:record fs) -> (build-record-literal fs)
    ;; XXX the rest
    exp -> (error1 "unhandled literal type" exp)
    )

  (define ctype->literal
    (ctype:name name)    -> (literal:cons 'ctype 'name (list (literal:symbol name)))
    (ctype:int size s?)  -> (literal:cons 'ctype 'int (list (literal:int (cint-size size)) (literal:bool s?)))
    (ctype:array size t) -> (literal:cons 'ctype 'array (list (literal:int size) (ctype->literal t)))
    (ctype:pointer t)    -> (literal:cons 'ctype 'pointer (list (ctype->literal t)))
    (ctype:struct name)  -> (literal:cons 'ctype 'struct (list (literal:symbol name)))
    (ctype:union name)   -> (literal:cons 'ctype 'union (list (literal:symbol name)))
    )

  ;; purpose: when we need compile time metadata at runtime.
  ;; currently, the only use for this is to fetch the list of
  ;;   FFI interfaces needed by this compilation unit.
  ;; eventually, we might want to expose data that is computed
  ;;   later in the compilation process, and this function should
  ;;   be moved to another file.
  (define get-compile-time-meta
    'ffi-interfaces
    -> (sexp:list (map sexp:symbol (cmap/keys the-context.ffi-map)))
    x
    -> (error1 "get-compile-time-meta: unknown key" x)
    )

  (define (get-formals l)
    (define p
      (sexp:symbol formal) acc -> (list:cons formal acc)
      _                    acc -> (error1 "malformed formal" l))
    (reverse (fold p '() l)))

  ;; sort the inits so that all function definitions come first.
  (define (sort-fix-inits names inits)
    (let ((names0 '())
          (names1 '())
          (inits0 '())
          (inits1 '())
          (n (length names)))
      (for-range
          i n
	(let ((name (nth names i))
	      (init (nth inits i)))
	  (match (noderec->t init) with
	    (node:function _ _) -> (begin (push! names0 name) (push! inits0 init))
	    _			-> (begin (push! names1 name) (push! inits1 init)))))
      (:sorted-fix (append (reverse names0) (reverse names1))
                   (append (reverse inits0) (reverse inits1)))))

  (define (unpack-bindings bindings)
    (let loop ((l bindings)
               (names '())
               (inits '()))
      (match l with
        () -> (:pair (reverse names) (reverse inits))
        ((sexp:list ((sexp:symbol name) init)) . l)
        -> (loop l (list:cons name names) (list:cons init inits))
        _ -> (error1 "unpack-bindings" (format (join repr " " l)))
        )))

  (define join-cexp-template
    (sexp:string result) -> result
    (sexp:list parts)
    -> (string-join
        (map
         (lambda (x)
           (match x with
             (sexp:string part) -> part
             _ -> (error1 "cexp template must be a list of strings" x)))
         parts)
        ", "
        )
    x -> (error1 "malformed cexp template" x))

  (define (build-record fields)
    ;; (printf "build-record.  can-haz? " (bool (can-haz-literal-fields? fields)) "\n")
    ;; (printf "      record = {" (join repr-field " " fields) "}\n")
    (if (can-haz-literal-fields? fields)
        (node/literal (build-record-literal fields))
        (foldr (lambda (field rest)
                 (match field with
                   (field:t name value)
                   -> (node/primapp '%rextend
                                    (sexp:symbol name)
                                    (list rest (walk value)))))
               (node/primapp '%rmake (sexp:bool #f) '())
               fields)))

  (define (build-vector vals)
    (if (every? can-haz-literal? vals)
        (node/literal (build-literal (sexp:vector vals)))
        ;; last-second magic here
        (walk (sexp (sym 'list->vector) (make-list vals)))))

  ;; given a list of sexp, return runtime code to build that as a list.
  ;; (i.e., this is the compiler's version of the LIST macro).
  (define (make-list* val acc)
    (sexp (sexp:cons 'list 'cons) val acc))

  (define (make-list vals)
    (foldr make-list* (sexp (sexp:cons 'list 'nil)) vals))

  ;; sexp->node actual
  (define walk*
    (sexp:symbol s)     -> (node/varref s)
    (sexp:string s)     -> (node/literal (literal:string s))
    (sexp:int n)        -> (node/literal (literal:int n))
    (sexp:char c)       -> (node/literal (literal:char c))
    (sexp:bool b)       -> (node/literal (literal:bool b))
    (sexp:undef)        -> (node/literal (literal:undef))
    (sexp:record fl)    -> (build-record fl)
    (sexp:vector l)     -> (build-vector l)
    (sexp:attr exp sym) -> (node/primapp '%raccess (sexp:symbol sym) (list (walk exp)))
    (sexp:cons dt alt)  -> (node/varref (string->symbol (format (sym dt) ":" (sym alt))))
    (sexp:list l)
    -> (match l with
         ((sexp:symbol 'begin) . exps)                -> (node/sequence (map walk exps))
         ((sexp:symbol 'set!) (sexp:symbol name) arg) -> (node/varset name (walk arg))
         ((sexp:symbol 'quote) arg)                   -> (node/literal (build-literal arg))
         ((sexp:symbol 'literal) arg)                 -> (node/literal (build-literal arg))
         ((sexp:symbol 'if) test then else)           -> (node/if (walk test) (walk then) (walk else))
         ((sexp:symbol '%%sexp) . exps)               -> (node/literal (unsexp-list exps))
         ((sexp:symbol '%typed) type exp)
         -> (let ((exp0 (walk exp)))
              ;;(printf "user type in expression: " (repr type) "\n")
              (set-node-type! exp0 (parse-type type))
              exp0)
         ((sexp:symbol '%%cexp) sig template . args)
         -> (let ((scheme (parse-cexp-sig sig)))
              (match scheme with
                (:scheme gens type)
                -> (node/cexp gens type (join-cexp-template template) (map walk args))))
         ((sexp:symbol '%%ffi) (sexp:symbol name) sig . args)
         -> (let ((scheme (parse-cexp-sig sig)))
              (match scheme with
                (:scheme gens type)
                -> (node/ffi gens type name (map walk args))))
         ((sexp:symbol '%%ffitype) ctype)
         -> (node/literal (ctype->literal (parse-ctype ctype)))
         ((sexp:symbol '%%compile-time-meta) (sexp:list ((sexp:symbol 'quote) (sexp:symbol name))))
         -> (node/literal (unsexp (get-compile-time-meta name)))
         ((sexp:symbol '%nvcase) (sexp:symbol dt) val-exp (sexp:list tags) (sexp:list arities) (sexp:list alts) ealt)
         -> (node/nvcase dt (map sexp->symbol tags) (map sexp->int arities) (walk val-exp) (map walk alts) (walk ealt))
         ((sexp:symbol 'function) (sexp:symbol name) (sexp:list formals) type . body)
         -> (node/function name (get-formals formals) type (node/sequence (map walk body)))
         ((sexp:symbol 'fix) (sexp:list names) (sexp:list inits) . body)
         -> (match (sort-fix-inits (get-formals names) (map walk inits)) with
              (:sorted-fix names inits)
              -> (node/fix names inits (node/sequence (map walk body))))
         ((sexp:symbol 'let-splat) (sexp:list bindings) . body)
         -> (match (unpack-bindings bindings) with
              (:pair names inits)
              -> (node/let names (map walk inits) (node/sequence (map walk body))))
         ((sexp:symbol 'letrec) (sexp:list bindings) . body)
         -> (match (unpack-bindings bindings) with
              (:pair names inits)
              -> (node/fix names (map walk inits) (node/sequence (map walk body))))
         ((sexp:symbol 'let-subst) (sexp:list ((sexp:symbol from) (sexp:symbol to))) body)
         -> (node/subst from to (walk body))
         ((sexp:symbol 'let-subst) . _)
         -> (error1 "syntax error (let-subst)" (format (join repr " " l)))
         ((sexp:cons 'nil alt) . rands)
         -> (node/primapp '%vcon (sexp (sexp:symbol alt) (sexp:int (length rands))) (map walk rands))
         ((sexp:cons dt alt) . rands)
         -> (if (can-haz-literal? (sexp:list l))
                (node/literal (build-literal (sexp:list l)))
                ;; this will inline all constructors.  not a good idea with the bytecode
                ;;  backend because it leads to runaway register allocation.
                (match the-context.options.backend with
                  (backend:bytecode) -> (node/call (walk (sexp:cons dt alt)) (map walk rands))
                  _                  -> (node/primapp '%dtcon (sexp:cons dt alt) (map walk rands)))
                )
         ;;-> (node/call (walk (sexp:cons dt alt)) (map walk rands))
         ((sexp:symbol name) . rands)
         -> (if (eq? (string-ref (symbol->string name) 0) #\%)
                (match rands with
                  (params . rands)
                  -> (node/primapp name params (map walk rands))
                  _ -> (error1 "null primapp missing params?" l))
                (node/call (node/varref name) (map walk rands)))
         ;; all other call types
         (rator . rands)
         -> (node/call (walk rator) (map walk rands))
         ;;_ -> (error1 "syntax error 1: " l)
         _ -> (raise (:Node/BadExpression l 3))
         )
    )

  (define (walk exp)
    (try
     (walk* exp)
     except
     (:Node/BadExpression x n)
     -> (if (= n 0)
            (error1 "bad expression compiling " x)
            (begin
              (printf "bad exp " (repr exp) "\n")
              (raise (:Node/BadExpression x (- n 1)))))
     ))
  (walk sexp)
  )

(define unsexp-list
  ()        -> (literal:cons 'list 'nil '())
  (hd . tl) -> (literal:cons 'list 'cons (list (unsexp hd) (unsexp-list tl)))
  )

(define unsexp
  (sexp:string s)  -> (literal:cons 'sexp 'string (list (literal:string s)))
  (sexp:int n)     -> (literal:cons 'sexp 'int (list (literal:int n)))
  (sexp:char c)    -> (literal:cons 'sexp 'char (list (literal:char c)))
  (sexp:bool b)    -> (literal:cons 'sexp 'bool (list (literal:bool b)))
  (sexp:undef)     -> (literal:cons 'sexp 'undef '())
  (sexp:symbol s)  -> (literal:cons 'sexp 'symbol (list (literal:symbol s)))
  (sexp:list l)    -> (literal:cons 'sexp 'list (list (unsexp-list l)))
  (sexp:vector l)  -> (literal:cons 'sexp 'vector (map unsexp l))
  (sexp:attr b n)  -> (literal:cons 'sexp 'attr (list (unsexp b) (literal:symbol n)))
  (sexp:cons d a)  -> (literal:cons 'sexp 'cons (list (literal:symbol d) (literal:symbol a)))
  exp -> (error1 "unsexp: unhandled literal type" exp)
  )

(define (rename-variables n)

  (define make-vardef
    (let ((counter (make-counter 0)))
      (lambda (name)
        (let ((serial (counter.inc))
              (frobbed (string->symbol (format (sym name) "_" (int serial)))))
          {name=name name2=frobbed assigns='() refs='() serial=serial}
          ))
      ))

  (define (check-for-duplicates names)
    (let ((nmap (tree:empty)))
      (for-list name names
        (match (tree/member nmap symbol-index-cmp name) with
          (maybe:yes other) -> (raise (:DuplicateName name other))
          (maybe:no)    -> (tree/insert! nmap symbol-index-cmp name name)
          ))))

  (define (rename-all exps lenv)
    (for-each (lambda (exp) (rename exp lenv)) exps))

  (define (rename exp lenv)

    (define (lookup name)
      (let loop0 ((lenv lenv))
        (match lenv with
          ()		 -> (maybe:no)
          (rib . next) -> (let loop1 ((l rib))
                            (match l with
                              ()	-> (loop0 next)
                              (vd . tl) -> (if (eq? name vd.name)
                                               (maybe:yes vd)
                                               (loop1 tl)))))))

    (match (noderec->t exp) with
      (node:function name formals)
      -> (let ((rib (map make-vardef formals))
               (name2 (match (lookup name) with
                        (maybe:no) -> (if (eq? name 'lambda)
                                          (string->symbol (format "lambda_" (int (noderec->id exp))))
                                          name)
                        (maybe:yes vd) -> vd.name2)))
           (set-node-t! exp (node:function name2 (map (lambda (x) x.name2) rib)))
           (rename-all (noderec->subs exp) (list:cons rib lenv)))
      (node:fix names)
      -> (let ((_ (check-for-duplicates names))
               (rib (map make-vardef names)))
           ;; in this one, the <inits> namespace is renamed, too
           (set-node-t! exp (node:fix (map (lambda (x) x.name2) rib)))
           (rename-all (noderec->subs exp) (list:cons rib lenv)))
      (node:let names) ;; this one is tricky!
      -> (match (unpack-fix (noderec->subs exp)) with
           (:fixsubs body inits)
           -> (let ((rib '())
                    (n (length inits)))
                (for-range
                    i n
                  ;; add each name only after its init
                  (rename (nth inits i) (list:cons rib lenv))
                  (set! rib (list:cons (make-vardef (nth names i)) rib)))
                ;; now that all the inits are done, rename the bindings and body
                (set-node-t! exp (node:let (map (lambda (x) x.name2) (reverse rib))))
                (rename body (list:cons rib lenv))))
      (node:varref name)
      -> (match (lookup name) with
           (maybe:no) -> #u ;; can't rename it if we don't know what it is
           (maybe:yes vd) -> (set-node-t! exp (node:varref vd.name2)))
      (node:varset name)
      -> (begin (match (lookup name) with
                  (maybe:no) -> #u
                  (maybe:yes vd) -> (set-node-t! exp (node:varset vd.name2)))
                (rename-all (noderec->subs exp) lenv))
      _ -> (rename-all (noderec->subs exp) lenv)
      )
    )

  (try
   (rename n '())
   ;; XXX when symbols get file/pos info this should make a better error message.
   except (:DuplicateName name other)
   -> (error1 "duplicate name: " name)
   )
  )

;; walk the node tree, applying subst nodes
(define (apply-substs exp)

  ;; could we do this more easily by flattening the environment and just using member?
  (define shadow
    names ()		-> (list:nil)
    names (pair . tail) -> (if (not (member-eq? pair.from names))
			       (list:cons pair (shadow names tail))
			       (shadow names tail)))

  (define lookup
    name ()	       -> name
    name (pair . tail) -> (if (eq? name pair.from)
			      pair.to
			      (lookup name tail)))

  (define (walk exp lenv)
    (let/cc return
	(match (noderec->t exp) with
	  (node:fix formals)	    -> (set! lenv (shadow formals lenv))
	  (node:let formals)	    -> (set! lenv (shadow formals lenv))
	  (node:function _ formals) -> (set! lenv (shadow formals lenv))
	  (node:subst from to)	    -> (begin
					 (set! lenv (list:cons {from=from to=(lookup to lenv)} lenv))
					 (return (walk (car (noderec->subs exp)) lenv)))
	  (node:varref name)	    -> (set-node-t! exp (node:varref (lookup name lenv)))
	  (node:varset name)	    -> (set-node-t! exp (node:varset (lookup name lenv)))
	  _ -> #u
	  )
      (set-node-subs! exp (map (lambda (x) (walk x lenv)) (noderec->subs exp)))
      exp))

  (walk exp '())
  )
