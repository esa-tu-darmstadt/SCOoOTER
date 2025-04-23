package BuildList;

// Allows to build a list using a single line of elements
// See BuildVector in the standard library

import List::*;
import ListN::*;
import BuildVector::*;
import Vector::*;

// define a typeclass for list generation
typeclass BuildList#(type a, type r)
   dependencies (r determines (a));
   function r buildList_(List#(a) v, a x);
endtypeclass

// add an element to a list through the typeclass
instance BuildList#(a,List#(a));
   function List#(a) buildList_(List#(a) v, a x);
      return List::reverse(List::cons(x,v));
   endfunction
endinstance

// expand the typeclass definition to allow for addition of multiple elements
instance BuildList#(a,function r f(a y)) provisos(BuildList#(a,r));
   function function r f(a y) buildList_(List#(a) v, a x);
      return buildList_(List::cons(x,v));
   endfunction
endinstance

// wrap the typeclass in a function call
function r list(a x) provisos(BuildList#(a,r));
   List#(a) empty = tagged Nil;
   return buildList_(empty,x);
endfunction

// same for ListN, an alternative BSV list implementation
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