# -*- Mode: Python -*-

# experimenting with the idea of using a kind of 'path compression' on static environment links.

# here we use a link design where the second pointer points halfway up the stack.

class link:
    def __init__ (self, data, next):
        self.data = data
        self.next0 = next
        if next:
            self.n = next.n + 1
        else:
            self.n = 1
        # ok, for next1 we want to point halfway back to the top.
        n1 = self.n / 2
        # technique one: count by ones.
        n2 = n1
        node = self
        while n2:
            node = node.next0
            n2 -= 1
        self.next1 = node

    def __repr__ (self):
        return '{%d.%d}' % (self.data, self.n)

    def path (self, count):
        # return a path to <count> levels up.
        # path0 is one link at a time.
        n0 = count
        node = self
        path0 = '0' * count
        while n0:
            node = node.next0
            n0 -= 1
        node0 = node
        
        # path1 uses the hops.
        path1 = []
        node = self
        n1 = count
        while n1:
            delta = node.n - node.next1.n
            if delta <= n1:
                n1 -= delta
                node = node.next1
                path1.append ('1')
            else:
                node = node.next0
                path1.append ('0')
                n1 -= 1
        node1 = node
        path1 = ''.join (path1)
        assert (node0 is node1)
        return path0, path1

# here we use a design that uses a fixed delta.

class linkf:

    HOP = 4

    def __init__ (self, data, next):
        self.data = data
        self.next0 = next
        if next and next.n >= self.HOP:
            node = next
            for i in range (self.HOP - 1):
                node = node.next0
            self.next1 = node
        else:
            self.next1 = None

        if next:
            self.n = next.n + 1
        else:
            self.n = 1

    def __repr__ (self):
        return '{%d.%d}' % (self.data, self.n)

    def path (self, count):
        # return a path to <count> levels up.
        # path0 is one link at a time.
        n0 = count
        node = self
        path0 = '0' * count
        while n0:
            node = node.next0
            n0 -= 1
        node0 = node
        
        # path1 uses the hops.
        path1 = []
        node = self
        n1 = count

        while n1 >= self.HOP:
            node = node.next1
            n1 -= self.HOP
            path1.append ('1')
        while n1:
            node = node.next0
            n1 -= 1
            path1.append ('0')
        node1 = node
        path1 = ''.join (path1)
        assert (node0 is node1)
        return path0, path1

def chain (n):
    all = []
    l = None
    for i in range (n):
        l = link (i, l)
        all.append (l)
    return all
        
def chainf (n):
    all = []
    l = None
    for i in range (n):
        l = linkf (i, l)
        all.append (l)
    return all

def test():
    l = chain (20)
    sum = 0
    for i in range (17):
        p0, p1 = l[-1].path (i)
        sum += len (p1)
    print sum

def testf():
    for hop in range (2,8):
        linkf.HOP = hop
        l = chainf (20)
        sum = 0
        for i in range (17):
            p0, p1 = l[-1].path (i)
            sum += len (p1)
        print hop, sum

    
