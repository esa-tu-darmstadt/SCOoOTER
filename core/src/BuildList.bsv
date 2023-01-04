package BuildList;

// See BuildVector in the standard library

import List::*;
import ListN::*;

typeclass BuildList#(type a, type r)
   dependencies (r determines (a));
   function r buildList_(List#(a) v, a x);
endtypeclass

instance BuildList#(a,List#(a));
   function List#(a) buildList_(List#(a) v, a x);
      return List::reverse(List::cons(x,v));
   endfunction
endinstance

instance BuildList#(a,function r f(a y)) provisos(BuildList#(a,r));
   function function r f(a y) buildList_(List#(a) v, a x);
      return buildList_(List::cons(x,v));
   endfunction
endinstance

function r list(a x) provisos(BuildList#(a,r));
   List#(a) empty = tagged Nil;
   return buildList_(empty,x);
endfunction




typeclass BuildListN#(type a, type r, numeric type n)
   dependencies (r determines (a,n));
   function r buildListN_(ListN#(n,a) v, a x);
endtypeclass

instance BuildListN#(a,ListN#(m,a),n) provisos(Add#(n,1,m));
   function ListN#(m,a) buildListN_(ListN#(n,a) v, a x);
      return ListN::reverse(ListN::cons(x,v));
   endfunction
endinstance

instance BuildListN#(a,function r f(a y),n) provisos(BuildListN#(a,r,m), Add#(n,1,m));
   function function r f(a y) buildListN_(ListN#(n,a) v, a x);
      return buildListN_(ListN::cons(x,v));
   endfunction
endinstance

function r listn(a x) provisos(BuildListN#(a,r,0));
   return buildListN_(nil,x);
endfunction

endpackage