# -*- Mode: Python; coding: utf-8 -*-

is_a = isinstance

class TypeError (Exception):
    pass

# 'itypes' since 'types' is a standard python module

class _type:
    def __iter__ (self):
        return walk_type (self)
    def sub (self, other):
        return False

class t_base (_type):
    name = 'base'
    code = 'b'
    def __cmp__ (self, other):
        return cmp (self.__class__, other.__class__)
    def __repr__ (self):
        return self.name
    def __hash__ (self):
        return hash (self.name)
    def sub (self, other):
        # cheap implementation of the subtyping relationship
        return issubclass (self.__class__, other.__class__)

class t_int (t_base):
    name = 'int'

class t_char (t_base):
    name = 'char'

class t_string (t_base):
    name = 'string'

class t_undefined (t_base):
    name = 'undefined'

class t_continuation (t_base):
    name = 'continuation'

# XXX may use product() instead...
class t_unit (t_base):
    name = 'unit'

# meant only for (vector int16)
class t_int16 (t_int):
    name = 'int16'

base_types = {
    'int' : t_int(),
    # bool now has a proper datatypes
    #'bool' : t_bool(),
    'char' : t_char(),
    'string' : t_string(),
    'undefined' : t_undefined(),
    'unit': t_unit(),
    'continuation' : t_continuation(),
    # now a proper datatype
    #'symbol' : t_symbol(),
    'int16' : t_int16(),
    }

def base_n (n, base, digits):
    # return a string representation of <n> in <base>, using <digits>
    s = []
    while 1:
        n, r = divmod (n, base)
        s.insert (0, digits[r])
        if not n:
            break
    return ''.join (s)

class t_var (_type):
    next = None
    rank = -1
    letters = 'abcdefghijklmnopqrstuvwxyz'
    eq = None
    counter = 1
    in_u = False
    node = None
    val = None
    code = 'v'
    mv = None
    pending = False
    def __init__ (self):
        self.id = t_var.counter
        t_var.counter += 1
    def __repr__ (self):
        return base_n (self.id, len(self.letters), self.letters)

class t_predicate (_type):
    code = 'p'
    def __init__ (self, name, args):
        self.name = name
        if self.name in ('rlabel', 'rdefault'):
            self.code = 'R'
        self.args = tuple (args)
    def __repr__ (self):
        # special cases
        if self.name == 'arrow':
            if len(self.args) == 2:
                return '(%r->%r)' % (self.args[1], self.args[0])
            else:
                return '(%r->%r)' % (self.args[1:], self.args[0])
        #elif self.name == 'rproduct' and len(self.args) == 1:
        #    return '{%s}' % (rlabels_repr (self.args[0]),)
        else:
            return '%s(%s)' % (self.name, ', '.join ([repr(x) for x in self.args]))

def walk_type (t):
    yield t
    if is_a (t, t_predicate):
        for arg in t.args:
            for x in walk_type (arg):
                yield x


def rlabels_repr (t):
    r = []
    while 1:
        if is_pred (t, 'rlabel'):
            lname, ltype, t = t.args
            if is_pred (ltype, 'pre'):
                # normal case
                r.append ('%s=%r' % (lname, ltype.args[0]))
            elif is_pred (ltype, 'abs'):
                r.append ('%s=#f' % (lname,))
            else:
                r.append ('...')
                break
        elif is_pred (t, 'rdefault'):
            if is_pred (t.args[0], 'abs'):
                # normal case
                break
            else:
                r.append (repr (t))
                break
        else:
            r.append ('...')
            break
    r.sort()
    return ' '.join (r)

def is_pred (t, *p):
    # is this a predicate from the set <p>?
    return is_a (t, t_predicate) and t.name in p

def arrow (*sig):
    # sig = (<result_type>, <arg0_type>, <arg1_type>, ...)
    # XXX this might be more clear as (<arg0>, <arg1>, ... <result>)
    return t_predicate ('arrow', sig)
    
def vector (type):
    return t_predicate ('vector', (type,))

def product (*args):
    # a.k.a. 'Π'
    return t_predicate ('product', args)

def sum (*args):
    # a.k.a. 'Σ'
    # args = ((<tag>, <type>), ...)
    args.sort()
    return t_predicate ('sum', args)

# row types
def rproduct (*args):
    return t_predicate ('rproduct', args)

def rsum (row):
    return t_predicate ('rsum', (row,))

def rdefault (arg):
    # a.k.a. 'δ'
    return t_predicate ('rdefault', (arg,))

def rlabel (name, type, rest):
    return t_predicate ('rlabel', (name, type, rest))

def abs():
    return t_predicate ('abs', ())

def pre (x):
    return t_predicate ('pre', (x,))

# used to represent equirecursive types ('moo' is a pun on the 'μ' notation).
class moo_var (_type):
    counter = 1
    letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    code = 'm'
    def __init__ (self):
        # this id is probably redundant, given the presence of a real tvar here.
        self.id = moo_var.counter
        moo_var.counter += 1
        self.tvar = t_var()
    def __repr__ (self):
        return base_n (self.id, len(self.letters), self.letters)

def moo (mvar, x):
    return t_predicate ('moo', (mvar, x))

# an algebraic datatype
class datatype:

    # this is a hack to get the predefined tags for certain datatypes.
    # not sure what else would go in here...
    # XXX need a way to stop a user from defining a 'whacky' list type.
    builtin_tags = {
        'list': {'cons':'TC_PAIR', 'nil':'TC_NIL'},
        'bool': {'true':'PXLL_TRUE', 'false':'PXLL_FALSE'},
        'symbol': {'t':'TC_SYMBOL'},
        }

    def __init__ (self, context, name, alts, tvars):
        self.context = context
        self.name = name
        self.alts = alts
        self.tvars = tvars.values()
        self.scheme = t_predicate (name, self.tvars)
        self.constructors = {}
        self.tags = {}
        tags = self.builtin_tags.get (name, None)
        for i in range (len (alts)):
            # assign runtime tags in the order they're defined.
            # [other choices would be to sort alphabetically, and/or
            #  immediate vs tuple]
            altname, prod = alts[i]
            self.constructors[altname] = prod
            if tags:
                self.tags[altname] = tags[altname]
            else:
                self.tags[altname] = i
        self.uimm = self.optimize()
            
    def order_alts (self, alts):
        r = [None] * len (alts)
        for i in range (len (alts)):
            tag, alt = alts[i]
            r[self.tags[tag]] = alt
        return r

    def arity (self, alt):
        return len (self.constructors[alt])

    def optimize (self):
        # scan for the single-immediate optimization.
        # identify all single-item alternatives that hold
        #   an immediate type that we can discern with a
        #   run-time tag.
        # for example:
        #
        # (datatype thing (:number int) (:letter char))
        #
        # can be represented with no runtime overhead, because
        # both alternatives can be a simple immediate.

        if self.name == 'symbol':
            # XXX In this *particular* case, we want to avoid the UIMM
            #   hack, because the runtime knows about symbols already.
            return {}

        good = {}
        bad = set()
        for tag, prod in self.alts:
            if len(prod) == 1 and is_a (prod[0], t_base):
                ty = prod[0]
                if good.has_key (ty):
                    bad.add (ty)
                else:
                    good[ty] = tag
        # take out the bad apples
        for ty in bad:
            del good[ty]
        uimm = {}
        for k, v in good.iteritems():
            uimm[v] = k
        return uimm
