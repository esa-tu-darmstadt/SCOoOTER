package GetPutCustom;

/*

Custom GetPut interfaces and connectable instances. Used for dequeueing by amount.

*/

import Connectable :: *;

//own GetPut extension for deq with value
interface GetSC#(type element_type, type count_type);
    method element_type first();
    method Action deq(count_type count);
endinterface

//own GetPut extension for deq with value
interface PutSC#(type element_type, type count_type);
    method Action put(element_type x1);
    method count_type deq();
endinterface

instance Connectable#(GetSC#(element_type, count_type), PutSC#(element_type, count_type));
    module mkConnection#(GetSC#(element_type, count_type) get, PutSC#(element_type, count_type) put)(Empty);
        rule forward1; get.deq(put.deq()); endrule
        rule forward2; put.put(get.first()); endrule
    endmodule
endinstance

instance Connectable#(PutSC#(element_type, count_type), GetSC#(element_type, count_type));
    module mkConnection#(PutSC#(element_type, count_type) put, GetSC#(element_type, count_type) get)(Empty);
        mkConnection(get, put);
    endmodule
endinstance

endpackage