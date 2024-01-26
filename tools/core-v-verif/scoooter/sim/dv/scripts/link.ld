/* Copyright 2018 Google LLC
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http:*www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x2000;
  .text : { *(.text) }
  . = 0x400000;
  .tohost : { *(.tohost) }
  .page_table : { *(.page_table) }
  .data : { *(.data) }
  .user_stack : { *(.user_stack) }
  .kernel_data : { *(.kernel_data) }
  .kernel_stack : { *(.kernel_stack) }
  .bss : { *(.bss) }
  _end = .;
  .fill : { FILL(0xcccccccc); }
  . = 0x63ffff;
  .fill_end : { BYTE(0xcc); }
  . = 0x800000;
}
