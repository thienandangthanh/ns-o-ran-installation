/*
 * selftest-encoder: emits one "<id> <hdr_hex> <msg_hex>" line built with the
 * SIZE(8)-TimeStamp library: KPM IndicationHeader format1 (8-byte
 * colletStartTime) and IndicationMessage format1 (1 measInfo item with a
 * measName + one label, 1 measData record with an integer).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <E2SM-KPM-IndicationHeader.h>
#include <E2SM-KPM-IndicationHeader-Format1.h>
#include <E2SM-KPM-IndicationMessage.h>
#include <E2SM-KPM-IndicationMessage-Format1.h>
#include <MeasurementInfoList.h>
#include <MeasurementInfoItem.h>
#include <MeasurementDataItem.h>
#include <MeasurementRecordItem.h>
#include <LabelInfoItem.h>

static void hexout(const unsigned char *b, size_t n) {
	for (size_t i = 0; i < n; i++) printf("%02x", b[i]);
}

static size_t enc(asn_TYPE_descriptor_t *td, void *s, unsigned char *buf, size_t cap) {
	asn_enc_rval_t r = asn_encode_to_buffer(0, ATS_ALIGNED_BASIC_PER, td, s, buf, cap);
	if (r.encoded < 0) { fprintf(stderr, "encode failed: %s\n", r.failed_type ? r.failed_type->name : "?"); exit(1); }
	return (size_t)r.encoded;
}

int main(void) {
	unsigned char hb[512], mb[512];
	static const unsigned char ts[8] = {0, 0, 0, 1, 0x65, 0x4a, 0x3b, 0x2c};

	E2SM_KPM_IndicationHeader_t *h = calloc(1, sizeof *h);
	E2SM_KPM_IndicationHeader_Format1_t *h1 = calloc(1, sizeof *h1);
	h->indicationHeader_formats.present =
	    E2SM_KPM_IndicationHeader__indicationHeader_formats_PR_indicationHeader_Format1;
	h->indicationHeader_formats.choice.indicationHeader_Format1 = h1;
	OCTET_STRING_fromBuf(&h1->colletStartTime, (const char *)ts, 8);
	size_t hn = enc(&asn_DEF_E2SM_KPM_IndicationHeader, h, hb, sizeof hb);

	E2SM_KPM_IndicationMessage_t *m = calloc(1, sizeof *m);
	E2SM_KPM_IndicationMessage_Format1_t *m1 = calloc(1, sizeof *m1);
	m->indicationMessage_formats.present =
	    E2SM_KPM_IndicationMessage__indicationMessage_formats_PR_indicationMessage_Format1;
	m->indicationMessage_formats.choice.indicationMessage_Format1 = m1;
	MeasurementInfoItem_t *mi = calloc(1, sizeof *mi);
	mi->measType.present = MeasurementType_PR_measName;
	OCTET_STRING_fromBuf(&mi->measType.choice.measName, "DRB.UEThpDl", -1);
	LabelInfoItem_t *li = calloc(1, sizeof *li);
	li->measLabel.noLabel = calloc(1, sizeof(long));
	*li->measLabel.noLabel = 0;
	ASN_SEQUENCE_ADD(&mi->labelInfoList.list, li);
	m1->measInfoList = calloc(1, sizeof *m1->measInfoList);
	ASN_SEQUENCE_ADD(&m1->measInfoList->list, mi);
	MeasurementDataItem_t *di = calloc(1, sizeof *di);
	MeasurementRecordItem_t *ri = calloc(1, sizeof *ri);
	ri->present = MeasurementRecordItem_PR_integer;
	ri->choice.integer = 1234;
	ASN_SEQUENCE_ADD(&di->measRecord.list, ri);
	ASN_SEQUENCE_ADD(&m1->measData.list, di);
	size_t mn = enc(&asn_DEF_E2SM_KPM_IndicationMessage, m, mb, sizeof mb);

	printf("selftest ");
	hexout(hb, hn);
	printf(" ");
	hexout(mb, mn);
	printf("\n");
	return 0;
}
