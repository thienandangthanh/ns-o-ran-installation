// Probe helpers for zz_enb_probe_test.go (cgo is not allowed in a _test.go file); copied into the kpimon image's
// control/ only by tools/kpimon-enb-probe/run.sh, never part of the patch set.
package control

/*
#include <stdlib.h>
#include <e2sm/wrapper.h>
#cgo LDFLAGS: -le2smwrapper -lm
*/
import "C"
import (
	"fmt"
	"unsafe"
)

// EnbProbe: the eNB action definition from the config, and the one kpimon builds from a RAN Function Description.
func EnbProbe(defHex string) (string, string) {
	cfg := encodeActionFormat3ByID(enbKpmMeasurements.Ue)
	cs := C.CString(defHex)
	defer C.free(unsafe.Pointer(cs))
	r := C.encode_action_Definition(cs, C.int(3), C.ulong(granularityPeriodMs))
	var fromDef []int64
	for i := 0; i < int(r.length); i++ {
		fromDef = append(fromDef, int64(*(*int32)(unsafe.Pointer(uintptr(unsafe.Pointer(r.array)) + uintptr(i*4)))))
	}
	h := func(v []int64) string {
		s := ""
		for _, b := range v {
			s += fmt.Sprintf("%02x", b)
		}
		return s
	}
	return h(cfg), h(fromDef)
}

// EnbNamesFromDef: the cell and UE measurement names kpimon reads from a RAN Function Description.
func EnbNamesFromDef(defHex string) ([]string, []string) {
	cs := C.CString(defHex)
	defer C.free(unsafe.Pointer(cs))
	r := C.buildRanCellUeKpi(cs)
	var cell, ue []string
	for _, v := range unsafe.Slice(r.cellKpi, r.cellKpiSize) {
		cell = append(cell, C.GoString(v))
	}
	for _, v := range unsafe.Slice(r.ueKpi, r.ueKpiSize) {
		ue = append(ue, C.GoString(v))
	}
	return cell, ue
}
