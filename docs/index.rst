.. SCOoOTER documentation master file, created by
   sphinx-quickstart on Wed Feb 28 14:18:57 2024.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to SCOoOTER's documentation!
====================================

SCOoOTER (Speculative Configurable Out of Order Teaching-Enhanced RISC-V Processor) is an RV32I[M][A]_zicsr RISC-V processor specifically aimed at education and classroom use.
SCOoOTER uses a dynamic pipeline architecture akin of modern, reordering, superscalar processors. Many aspects of the pipeline can be configured such that different design decisions can be explored. Before using SCOoOTER, you should gain the necessary prerequisite knowledge. We recommend the following literature:

- John L. Hennessy and David A. Patterson. 2019. Computer Architecture: A Quantitative Approach (6th ed.).
- Rishiyur S. Nikhil. 2024. Learn RISC-V CPU Implementation and BSV. Bluespec Inc. https://github.com/rsnikhil/Learn_Bluespec_and_RISCV_Design/blob/main/Book_BLang_RISCV.pdf
- Arvind, Rishiyur S. Nikhil, Joel S. Emer, and Murali Vijayaraghavan. 2011. Computer architecture: A Constructive Approach.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   architecture/overview
   architecture/features
   usage/quickstart
   usage/pipeview
   developer_guide/code_overview


Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
