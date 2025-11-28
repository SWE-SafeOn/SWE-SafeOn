package com.example.demo.mqtt;

import com.example.demo.config.MlMqttProperties;
import com.example.demo.domain.PacketMeta;
import com.example.demo.repository.PacketMetaRepository;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class MlRequestPublisher {

    private final PacketMetaRepository packetMetaRepository;
    private final MlMqttClientService mqttClientService;
    private final MlMqttProperties mqttProperties;
    private final ObjectMapper objectMapper;

    @Transactional(readOnly = true)
    public void publishPacketMetaJsonl() {
        List<PacketMeta> rows = packetMetaRepository.findAll();
        publishPacketMetaJsonl(rows);
    }

    public void publishPacketMetaJsonl(List<PacketMeta> rows) {
        String topic = resolveTopic();
        if (rows == null || rows.isEmpty()) {
            log.info("No packet_meta rows to publish to MQTT. topic={}", topic);
            return;
        }

        StringBuilder jsonlBuilder = new StringBuilder();
        for (PacketMeta meta : rows) {
            String jsonLine = toJson(meta);
            if (jsonLine != null) {
                jsonlBuilder.append(jsonLine).append("\n");
            }
        }

        if (jsonlBuilder.length() == 0) {
            log.warn("All packet_meta rows failed serialization. Nothing published.");
            return;
        }

        mqttClientService.publish(topic, jsonlBuilder.toString());
    }

    private String resolveTopic() {
        String topic = mqttProperties.getMlRequestTopic();
        if (!StringUtils.hasText(topic)) {
            throw new IllegalStateException("MQTT ml-request topic is not configured.");
        }
        return topic;
    }

    private String toJson(PacketMeta meta) {
        try {
            return objectMapper.writeValueAsString(new PacketMetaPayload(
                    meta.getPacketMetaId(),
                    meta.getSrcIp(),
                    meta.getDstIp(),
                    meta.getSrcPort(),
                    meta.getDstPort(),
                    meta.getProto(),
                    meta.getTimeBucket(),
                    meta.getStartTime(),
                    meta.getEndTime(),
                    meta.getDuration(),
                    meta.getPacketCount(),
                    meta.getByteCount(),
                    meta.getPps(),
                    meta.getBps()
            ));
        } catch (JsonProcessingException e) {
            log.warn("Failed to serialize packet_meta row, skipping. id={}", meta.getPacketMetaId(), e);
            return null;
        }
    }

    private record PacketMetaPayload(
            @JsonProperty("packet_meta_id") UUID packetMetaId,
            @JsonProperty("src_ip") String srcIp,
            @JsonProperty("dst_ip") String dstIp,
            @JsonProperty("src_port") Integer srcPort,
            @JsonProperty("dst_port") Integer dstPort,
            @JsonProperty("proto") String proto,
            @JsonProperty("time_bucket") String timeBucket,
            @JsonProperty("start_time") java.time.OffsetDateTime startTime,
            @JsonProperty("end_time") java.time.OffsetDateTime endTime,
            @JsonProperty("duration") Double duration,
            @JsonProperty("packet_count") Integer packetCount,
            @JsonProperty("byte_count") Long byteCount,
            @JsonProperty("pps") Double pps,
            @JsonProperty("bps") Double bps
    ) {
    }
}
