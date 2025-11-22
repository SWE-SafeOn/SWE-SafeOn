package com.example.demo.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "packet_meta")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PacketMeta {

    @Id
    @GeneratedValue(generator = "uuid2")
    @Column(name = "packet_meta_id")
    private UUID packetMetaId;

    @Column(name = "flow_id")
    private UUID flow;

    @Column(name = "src_ip")
    private String srcIp;

    @Column(name = "dst_ip")
    private String dstIp;

    @Column(name = "src_port")
    private Short srcPort;

    @Column(name = "dst_port")
    private Short dstPort;

    @Column(name = "proto")
    private String proto;

    @Column(name = "time_bucket")
    private String timeBucket;

    @Column(name = "start_time")
    private OffsetDateTime startTime;

    @Column(name = "end_time")
    private OffsetDateTime endTime;

    private Double duration;

    @Column(name = "packet_count")
    private Integer packetCount;

    @Column(name = "byte_count")
    private Long byteCount;

    private Double pps;

    private Double bps;

    private Integer label;

}
