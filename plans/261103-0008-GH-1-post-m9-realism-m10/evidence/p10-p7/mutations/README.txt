Mutation checks of the forwarding cases (suite indices 31-40) against the production per-bearer
functions, on the host green tree (4a0871d6 + the change). Each mutation was applied to the build
tree's copy of one production file only (never the worktree), the test-runner rebuilt, cases 31-40
run one per process (MC_CASE probe), the file restored and the tree rebuilt (mutate.sh).

m1 skip RemoveHeader in DeliverRlcForwardingBuffer          RED 31-34, 37-40 (SDU forwarding); 35-36 keep the header by design
m2 strip with LtePdcpHeader in DeliverRlcForwardingBuffer   RED 31-34, 37-40 (metadata: the NR header item is not removed)
m3 keep packet tags in DeliverRlcForwardingBuffer           RED 31-40
m4 always strip (ignore removePdcpHeader)                   RED 35-36 (peer McUePdcp aborts: payload read as a Control PDU)
m5 reverse the reassembled SDU order in Collect...          RED 31-33, 35, 37-39 (sent cases); queued cases unaffected
m6 drop the RLC AM's last-started-SDU copy in Collect...    RED 31-33, 35, 37-39 (count 4, pinned 5); queued cases unaffected
m7 LteUeRrc::CopyRlcBuffers names LtePdcpHeader             COMPILE ERROR (IfNrPdcpHeader constraint)
m9 RlcPdusToRlcSdus<LtePdcpHeader> inside Collect...        COMPILE ERROR (IfNrPdcpHeader constraint)
m8 UeManager::ForwardRlcBuffers dispatch flag inverted      GREEN: the per-call dispatch lambdas/flags of the two RRC
                                                            methods are not exercised by this suite (uncovered)
