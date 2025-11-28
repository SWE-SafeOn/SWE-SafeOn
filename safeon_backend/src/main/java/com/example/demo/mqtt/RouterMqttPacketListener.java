package com.example.demo.mqtt;

import com.example.demo.config.RouterMqttProperties;
import com.example.demo.domain.Device;
import com.example.demo.domain.PacketMeta;
import com.example.demo.repository.DeviceRepository;
import com.example.demo.repository.PacketMetaRepository;
import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class RouterMqttPacketListener implements MqttPacketListener {

    private final RouterMqttProperties mqttProperties;
    private final DeviceRepository deviceRepository;
    private final PacketMetaRepository packetMetaRepository;
    private final MlRequestPublisher mlRequestPublisher;
    private final ObjectMapper objectMapper;

    @Override
    @Transactional
    public void onPacketReceived(String topic, byte[] payload) {
        String message = new String(payload, StandardCharsets.UTF_8);
        try {
            if (matches(topic, mqttProperties.getDeviceTopic())) {
                handleDeviceDiscovery(message);
            } else if (matches(topic, mqttProperties.getFlowTopic())) {
                handleFlowPackets(message);
            } else {
                log.debug("MQTT message ignored. topic={}", topic);
            }
        } catch (Exception e) {
            log.warn("Failed to process MQTT message. topic={}, payload={}", topic, message, e);
        }
    }

    private boolean matches(String topic, String expected) {
        return StringUtils.hasText(expected) && expected.equals(topic);
    }

    private void handleDeviceDiscovery(String message) throws Exception {
        DeviceDiscoveryPayload payload = objectMapper.readValue(message, DeviceDiscoveryPayload.class);
        if (!StringUtils.hasText(payload.macAddress())) {
            throw new IllegalArgumentException("macAddress is required for discovered device.");
        }

        String status = StringUtils.hasText(payload.status()) ? payload.status() : "connect";

        deviceRepository.findByMacAddress(payload.macAddress())
                .ifPresentOrElse(
                        existing -> {
                            existing.updateStatus(status);
                            if (StringUtils.hasText(payload.ip())) {
                                existing.updateIp(payload.ip());
                            }
                            log.debug("Device already exists, updated status. mac={}, status={}", payload.macAddress(), status);
                        },
                        () -> {
                            Device device = Device.create(
                                    payload.macAddress(),
                                    payload.name(),
                                    payload.ip(),
                                    false,
                                    OffsetDateTime.now(),
                                    status
                            );
                            deviceRepository.save(device);
                            log.info("Discovered device saved via MQTT. mac={}, ip={}, status={}", payload.macAddress(), payload.ip(), status);
                        }
                );
    }

    private void handleFlowPackets(String message) {
        String[] lines = message.split("\\r?\\n");
        List<PacketMeta> entities = new ArrayList<>();

        for (String line : lines) {
            if (!StringUtils.hasText(line)) {
                continue;
            }
            try {
                FlowPacketPayload payload = objectMapper.readValue(line, FlowPacketPayload.class);
                OffsetDateTime start = resolveTime(payload.startTime());
                if (start == null) {
                    log.warn("Skip packet meta without start time. raw={}", line);
                    continue;
                }
                OffsetDateTime end = resolveTime(payload.endTime());

                entities.add(PacketMeta.builder()
                        .srcIp(payload.srcIp())
                        .dstIp(payload.dstIp())
                        .srcPort(payload.srcPort())
                        .dstPort(payload.dstPort())
                        .proto(payload.proto())
                        .timeBucket(payload.timeBucket())
                        .startTime(start)
                        .endTime(end)
                        .duration(payload.duration())
                        .packetCount(payload.packetCount())
                        .byteCount(payload.byteCount())
                        .pps(payload.pps())
                        .bps(payload.bps())
                        .build());
            } catch (Exception ex) {
                log.warn("Failed to parse flow packet line, skipping. raw={}", line, ex);
            }
        }

        if (!entities.isEmpty()) {
            packetMetaRepository.saveAll(entities);
            log.info("Saved {} packet_meta rows from MQTT.", entities.size());
            mlRequestPublisher.publishPacketMetaJsonl(entities);
        }
    }

    private OffsetDateTime resolveTime(String isoTime) {
        if (!StringUtils.hasText(isoTime)) {
            return null;
        }

        try {
            return OffsetDateTime.parse(isoTime);
        } catch (DateTimeParseException ignored) {
        }

        try {
            return LocalDateTime.parse(isoTime, DateTimeFormatter.ISO_LOCAL_DATE_TIME).atOffset(ZoneOffset.UTC);
        } catch (DateTimeParseException e) {
            log.warn("Cannot parse date time: {}", isoTime);
            return null;
        }
    }

    private record DeviceDiscoveryPayload(
            @JsonAlias({"macAddress", "mac_address", "mac"}) String macAddress,
            @JsonAlias({"name", "device_name"}) String name,
            @JsonAlias({"ip", "ip_address"}) String ip,
            @JsonAlias({"status"}) String status
    ) {
    }

    private record FlowPacketPayload(
            @JsonAlias({"src_ip", "srcIp"}) String srcIp,
            @JsonAlias({"dst_ip", "dstIp"}) String dstIp,
            @JsonAlias({"src_port", "srcPort"}) Integer srcPort,
            @JsonAlias({"dst_port", "dstPort"}) Integer dstPort,
            @JsonAlias({"proto", "protocol"}) String proto,
            @JsonAlias({"time_bucket", "timeBucket"}) String timeBucket,
            @JsonAlias({"start_time", "startTime"}) String startTime,
            @JsonAlias({"end_time", "endTime"}) String endTime,
            @JsonAlias({"duration"}) Double duration,
            @JsonAlias({"packet_count", "packetCount"}) Integer packetCount,
            @JsonAlias({"byte_count", "byteCount"}) Long byteCount,
            @JsonAlias({"pps"}) Double pps,
            @JsonAlias({"bps"}) Double bps
    ) {
    }
}
