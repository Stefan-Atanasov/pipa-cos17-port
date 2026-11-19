#!/bin/sh
# make_odm_from_stock.sh: assemble the beta4 odm tree from PixelOS odm + C.06 donor odm + author scripts. See make_from_stock.sh header.
# usage: OUT=/path/tree [B4=/path/beta4-odm-tree] [STANDIN=0|1] sh make_odm_from_stock.sh
exec env KIND=o sh "$(dirname "$0")/make_from_stock.sh"
