package SCOOOTER_riscv;

import BlueAXI :: *;
import Interfaces :: *;
import Fetch :: *;

module mkSCOOOTER_riscv(Top);

    IFU ifu <- mkFetch();

    interface ifu_axi = ifu.ifu_axi;

endmodule

endpackage
