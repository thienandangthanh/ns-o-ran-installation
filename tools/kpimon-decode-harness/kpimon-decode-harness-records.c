/*
 * --records output of kpimon-decode-harness: the decoded KPM record values of
 * an indication message (as kpimon reads them: Format1 measData items in
 * order, Format2 measData[0] records metric-major) and the decoded header
 * fields. REAL records are printed as the 16-hex-digit IEEE-754 bit pattern of
 * the double kpimon would read, so a caller can compare bit-exactly.
 */
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <E2SM-KPM-IndicationHeader-Format1.h>
#include <E2SM-KPM-IndicationMessage-Format1.h>
#include <E2SM-KPM-IndicationMessage-Format2.h>
#include <MeasurementDataItem.h>
#include <MeasurementRecordItem.h>
#include <MeasurementCondUEidItem.h>
#include <MatchingUEidList.h>
#include <MatchingUEidItem.h>
#include <UEID.h>
#include <UEID-GNB.h>
#include "kpimon-decode-harness.h"

static void print_record_list(const MeasurementRecord_t *rec) {
	for (int i = 0; i < rec->list.count; i++) {
		const MeasurementRecordItem_t *r = rec->list.array[i];
		if (i) putchar(',');
		if (r->present == MeasurementRecordItem_PR_integer) {
			printf("{\"t\":\"int\",\"v\":%lu}", (unsigned long)r->choice.integer);
		} else if (r->present == MeasurementRecordItem_PR_real) {
			uint64_t bits;
			memcpy(&bits, &r->choice.real, 8);
			printf("{\"t\":\"real\",\"bits\":\"%016" PRIx64 "\"}", bits);
		} else if (r->present == MeasurementRecordItem_PR_noValue) {
			printf("{\"t\":\"none\"}");
		} else {
			printf("{\"t\":\"other%d\"}", (int)r->present);
		}
	}
}

/* amf-UE-NGAP-ID of every gNB-UEID in the first measCondUEidList item, and
 * whether every item carries the same number of UE IDs. */
static void print_ue_ids(const E2SM_KPM_IndicationMessage_Format2_t *f2) {
	const MeasurementCondUEidList_t *l = &f2->measCondUEidList;
	int n0 = -1, same = 1;
	for (int i = 0; i < l->list.count; i++) {
		const MeasurementCondUEidItem_t *c = l->list.array[i];
		int n = c->matchingUEidList ? c->matchingUEidList->list.count : 0;
		if (n0 < 0) n0 = n; else if (n != n0) same = 0;
	}
	printf(",\"condItems\":%d,\"ueIdsPerItem\":%d,\"ueIdsUniform\":%s,\"amfUeNgapIds\":[", l->list.count, n0,
	       same ? "true" : "false");
	if (l->list.count > 0 && l->list.array[0]->matchingUEidList) {
		const MatchingUEidList_t *u = l->list.array[0]->matchingUEidList;
		for (int k = 0; k < u->list.count; k++) {
			const UEID_t *id = &u->list.array[k]->ueID;
			uintmax_t v = 0;
			if (id->present == UEID_PR_gNB_UEID && id->choice.gNB_UEID &&
			    asn_INTEGER2umax(&id->choice.gNB_UEID->amf_UE_NGAP_ID, &v) == 0)
				printf("%s%ju", k ? "," : "", v);
			else
				printf("%snull", k ? "," : "");
		}
	}
	printf("]");
}

void print_message_records(const E2SM_KPM_IndicationMessage_t *msg) {
	const struct E2SM_KPM_IndicationMessage__indicationMessage_formats *f = &msg->indicationMessage_formats;
	if (f->present == E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format1) {
		const E2SM_KPM_IndicationMessage_Format1_t *f1 = f->choice.indicationMessage_Format1;
		printf(",\"measDataItems\":%d,\"records\":[", f1->measData.list.count);
		for (int i = 0; i < f1->measData.list.count; i++) {
			if (i && f1->measData.list.array[i]->measRecord.list.count) putchar(',');
			print_record_list(&f1->measData.list.array[i]->measRecord);
		}
		printf("]");
		if (f1->granulPeriod) printf(",\"granulPeriod\":%lu", (unsigned long)*f1->granulPeriod);
	} else if (f->present == E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format2) {
		const E2SM_KPM_IndicationMessage_Format2_t *f2 = f->choice.indicationMessage_Format2;
		printf(",\"measDataItems\":%d,\"records\":[", f2->measData.list.count);
		if (f2->measData.list.count > 0) print_record_list(&f2->measData.list.array[0]->measRecord);
		printf("]");
		if (f2->granulPeriod) printf(",\"granulPeriod\":%lu", (unsigned long)*f2->granulPeriod);
		print_ue_ids(f2);
	}
}

void print_header_fields(const E2SM_KPM_IndicationHeader_t *hdr) {
	if (hdr->indicationHeader_formats.present !=
	    E2SM_KPM_IndicationHeader__indicationHeader_formats_PR_indicationHeader_Format1)
		return;
	const E2SM_KPM_IndicationHeader_Format1_t *h = hdr->indicationHeader_formats.choice.indicationHeader_Format1;
	printf(",\"header\":{\"ts_hex\":\"");
	for (size_t i = 0; i < h->colletStartTime.size; i++) printf("%02x", h->colletStartTime.buf[i]);
	printf("\"");
	if (h->senderName) { printf(",\"senderName\":"); json_octets(h->senderName->buf, h->senderName->size); }
	if (h->senderType) { printf(",\"senderType\":"); json_octets(h->senderType->buf, h->senderType->size); }
	if (h->vendorName) { printf(",\"vendorName\":"); json_octets(h->vendorName->buf, h->vendorName->size); }
	printf("}");
}
