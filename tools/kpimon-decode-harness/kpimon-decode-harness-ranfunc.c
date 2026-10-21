/*
 * --ranfunc mode of kpimon-decode-harness: decodes an E2SM-KPM RAN function
 * description (the ranFunctionDefinition octets of an E2SetupRequest) twice:
 *   1. "kpimon": by calling kpimon's own buildRanCellUeKpi(hex) from
 *      libe2smwrapper.so, exactly as kpimon's control.go does with the hex
 *      string e2mgr returns (wrapper.c:12-113). Note that kpimon passes the hex
 *      string LENGTH (2x the octet count) as the decode size; that is kept.
 *      Its stdout chatter is redirected to stderr.
 *   2. "strict": asn_decode with the true octet count; clean means RC_OK and
 *      consumed == length.
 * Output per line: {"id", "len", "strict":{code, consumed, shortName, oid,
 * description, instance, styles:[{type, actFmt, hdrFmt, msgFmt, n, names, ids}]},
 * "kpimon":{"cell":[names], "ue":[names]}}.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wrapper.h>
#include <E2SM-KPM-RANfunction-Description.h>
#include <RIC-ReportStyle-Item.h>
#include <MeasurementInfo-Action-Item.h>
#include "kpimon-decode-harness.h"

static void print_names(char **names, int n) {
	putchar('[');
	for (int i = 0; i < n; i++) {
		if (i) putchar(',');
		json_str(names[i] ? names[i] : "");
	}
	putchar(']');
}

static void print_strict(const unsigned char *b, long len) {
	E2SM_KPM_RANfunction_Description_t *d = NULL;
	asn_dec_rval_t r = asn_decode(0, ATS_ALIGNED_BASIC_PER, &asn_DEF_E2SM_KPM_RANfunction_Description,
	                              (void **)&d, b, (size_t)len);
	printf("\"strict\":{\"code\":\"%s\",\"consumed\":%ld",
	       r.code == RC_OK ? "RC_OK" : r.code == RC_WMORE ? "RC_WMORE" : "RC_FAIL", (long)r.consumed);
	if (r.code == RC_OK && d) {
		RANfunction_Name_t *n = &d->ranFunction_Name;
		printf(",\"shortName\":"); json_octets(n->ranFunction_ShortName.buf, n->ranFunction_ShortName.size);
		printf(",\"oid\":"); json_octets(n->ranFunction_E2SM_OID.buf, n->ranFunction_E2SM_OID.size);
		printf(",\"description\":"); json_octets(n->ranFunction_Description.buf, n->ranFunction_Description.size);
		if (n->ranFunction_Instance) printf(",\"instance\":%ld", *n->ranFunction_Instance);
		printf(",\"eventTriggerStyles\":%d", d->ric_EventTriggerStyle_List ? d->ric_EventTriggerStyle_List->list.count : 0);
		printf(",\"styles\":[");
		for (int i = 0; d->ric_ReportStyle_List && i < d->ric_ReportStyle_List->list.count; i++) {
			RIC_ReportStyle_Item_t *s = d->ric_ReportStyle_List->list.array[i];
			printf("%s{\"type\":%ld,\"name\":", i ? "," : "", s->ric_ReportStyle_Type);
			json_octets(s->ric_ReportStyle_Name.buf, s->ric_ReportStyle_Name.size);
			printf(",\"actFmt\":%ld,\"hdrFmt\":%ld,\"msgFmt\":%ld,\"n\":%d,\"names\":[", s->ric_ActionFormat_Type,
			       s->ric_IndicationHeaderFormat_Type, s->ric_IndicationMessageFormat_Type,
			       s->measInfo_Action_List.list.count);
			for (int j = 0; j < s->measInfo_Action_List.list.count; j++) {
				MeasurementInfo_Action_Item_t *it = s->measInfo_Action_List.list.array[j];
				if (j) putchar(',');
				json_octets(it->measName.buf, it->measName.size);
			}
			printf("],\"ids\":[");
			for (int j = 0; j < s->measInfo_Action_List.list.count; j++) {
				MeasurementInfo_Action_Item_t *it = s->measInfo_Action_List.list.array[j];
				printf("%s%ld", j ? "," : "", it->measID ? *it->measID : -1L);
			}
			printf("]}");
		}
		printf("]");
	}
	printf("}");
	ASN_STRUCT_FREE(asn_DEF_E2SM_KPM_RANfunction_Description, d);
}

int run_ranfunc_mode(void) {
	char *line = NULL;
	size_t cap = 0;
	while (getline(&line, &cap, stdin) > 0) {
		char *save = NULL, *id = strtok_r(line, " \t\r\n", &save), *hex = strtok_r(NULL, " \t\r\n", &save);
		if (!id || id[0] == '#' || !hex) continue;
		unsigned char *b = malloc(strlen(hex) / 2 + 2);
		long len = hex_decode(hex, b);
		printf("{\"id\":"); json_str(id);
		printf(",\"len\":%ld,", len);
		if (len < 0) { printf("\"strict\":{\"code\":\"BAD_HEX\"}}\n"); free(b); continue; }
		print_strict(b, len);

		/* kpimon's own path; its printf noise goes to stderr. */
		fflush(stdout);
		int saved = dup(1);
		dup2(2, 1);
		ranCellUeKpi_t k = buildRanCellUeKpi(hex);
		fflush(stdout);
		dup2(saved, 1);
		close(saved);
		printf(",\"kpimon\":{\"cell\":");
		print_names(k.cellKpi, k.cellKpiSize);
		printf(",\"ue\":");
		print_names(k.ueKpi, k.ueKpiSize);
		printf("}}\n");
		freeMemorydRanCellUeKpi(k);
		free(b);
	}
	free(line);
	return 0;
}
