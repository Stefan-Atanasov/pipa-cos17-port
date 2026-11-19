#!/bin/sh
# make_vendor_from_stock.sh: assemble the beta4 vendor tree from PixelOS + stock sources. See make_from_stock.sh header.
# usage: OUT=/path/tree [B4=/path/beta4-vendor-tree] [STANDIN=0|1] sh make_vendor_from_stock.sh
exec env KIND=v sh "$(dirname "$0")/make_from_stock.sh"
