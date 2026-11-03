// TestEnbProbe (run by tools/kpimon-enb-probe/run.sh inside the kpimon image, with /probe mounted): kpimon's eNB path
// (enb-kpm-measurements.json) must produce the Format 3 action definition and the name lists kpimon builds from the
// eNB agent's own RAN Function Description, and isEnbNode must tell an eNB record from an en-gNB one.
package control

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
)

func TestEnbProbe(t *testing.T) {
	granularityPeriodMs = 100
	def, _ := os.ReadFile("/probe/enb-ranfunc2.hex")
	a, b := EnbProbe(strings.TrimSpace(string(def)))
	fmt.Println("CONFIG_FORMAT3", a)
	fmt.Println("FROMDEF_FORMAT3", b)
	fmt.Println("EQUAL", a == b && a != "" && a != "00")
	if a != b || a == "" || a == "00" {
		t.Errorf("action definition from the config differs from the one from the RAN Function Description")
	}
	cell, ue := EnbNamesFromDef(strings.TrimSpace(string(def)))
	namesEqual := fmt.Sprint(cell) == fmt.Sprint(measNames(enbKpmMeasurements.Cell)) &&
		fmt.Sprint(ue) == fmt.Sprint(measNames(enbKpmMeasurements.Ue))
	fmt.Println("NAMES_EQUAL", namesEqual, len(cell), len(ue))
	if !namesEqual || len(ue) == 0 {
		t.Errorf("name lists from the config differ from the ones from the RAN Function Description")
	}
	fmt.Println("UE_NAMES", len(measNames(enbKpmMeasurements.Ue)), "CELL_NAMES", len(measNames(enbKpmMeasurements.Cell)))
	for _, f := range []string{"/probe/fixtures/e2mgr-nodeb-enb.json", "/probe/fixtures/e2mgr-nodeb-en-gnb.json"} {
		var r E2mgrResponse
		raw, _ := os.ReadFile(f)
		if err := json.Unmarshal(raw, &r); err != nil {
			t.Fatal(err)
		}
		fmt.Println("IS_ENB", f, isEnbNode(&r), r.NodeType, len(r.Gnb.RanFunctions))
		if isEnbNode(&r) != strings.HasSuffix(f, "-enb.json") {
			t.Errorf("isEnbNode(%s) = %v", f, isEnbNode(&r))
		}
	}
}
