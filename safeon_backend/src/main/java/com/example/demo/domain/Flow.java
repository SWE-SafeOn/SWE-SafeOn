package com.example.demo.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "flows")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Flow {

    @Id
    @GeneratedValue(generator = "uuid2")
    @Column(name = "flow_id")
    private UUID flowId;

    @Column(name = "flow_key")
    private String flowKey;

    @Column(name = "src_ip")
    private String srcIp;

    @Column(name = "dst_ip")
    private String dstIp;

    @Column(name = "src_port")
    private Short srcPort;

    @Column(name = "dst_port")
    private Short dstPort;

    @Column(name = "l4_proto")
    private String l4Proto;

    @Column(name = "start_ts")
    private OffsetDateTime startTs;

    @Column(name = "end_ts")
    private OffsetDateTime endTs;

    private Long bytes;

    private Long pkts;

}
