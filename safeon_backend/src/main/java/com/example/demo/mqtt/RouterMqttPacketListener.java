package com.example.demo.mqtt;

import com.example.demo.config.RouterMqttProperties;
import com.example.demo.domain.Alert;
import com.example.demo.domain.AnomalyScore;
import com.example.demo.domain.Device;
import com.example.demo.domain.PacketMeta;
import com.example.demo.domain.UserAlert;
import com.example.demo.repository.AlertRepository;
import com.example.demo.repository.AnomalyScoreRepository;
import com.example.demo.repository.DeviceRepository;
import com.example.demo.repository.PacketMetaRepository;
import com.example.demo.repository.UserAlertRepository;
import com.example.demo.repository.UserDeviceRepository;
import com.example.demo.service.DashboardService;
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
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
public class RouterMqttPacketListener implements MqttPacketListener {

    private final RouterMqttProperties mqttProperties;
    private final DeviceRepository deviceRepository;
    private final PacketMetaRepository packetMetaRepository;
    private final AnomalyScoreRepository anomalyScoreRepository;
    private final AlertRepository alertRepository;
    private final UserDeviceRepository userDeviceRepository;
    private final UserAlertRepository userAlertRepository;
    private final DashboardService dashboardService;
    private final MlRequestPublisher mlRequestPublisher;
    private final ObjectMapper objectMapper;

    @Override
    @Transactional
    public void onPacketReceived(String topic, byte[] payload) {
        String message = new String(payload, StandardCharsets.UTF_8);
        log.info("MQTT 메시지 수신. topic={}, payload={}", topic, message);
        try {
            if (matches(topic, mqttProperties.getDeviceTopic())) {
                handleDeviceDiscovery(message);
            } else if (matches(topic, mqttProperties.getFlowTopic())) {
                handleFlowPackets(message);
            } else {
                log.debug("처리 대상이 아닌 MQTT 메시지입니다. topic={}", topic);
            }
        } catch (Exception e) {
            log.warn("MQTT 메시지 처리에 실패했습니다. topic={}, payload={}", topic, message, e);
        }
    }

    private boolean matches(String topic, String expected) {
        return StringUtils.hasText(expected) && expected.equals(topic);
    }

    private void handleDeviceDiscovery(String message) throws Exception {
        DeviceDiscoveryPayload payload = objectMapper.readValue(message, DeviceDiscoveryPayload.class);
        if (!StringUtils.hasText(payload.macAddress())) {
            throw new IllegalArgumentException("macAddress는 필수 값입니다.");
        }

        String status = StringUtils.hasText(payload.status()) ? payload.status() : "connect";

        deviceRepository.findByMacAddress(payload.macAddress())
                .ifPresentOrElse(
                        existing -> {
                            existing.updateStatus(status);
                            if (StringUtils.hasText(payload.ip())) {
                                existing.updateIp(payload.ip());
                            }
                            log.debug("이미 존재하는 디바이스여서 상태만 갱신했습니다. mac={}, status={}", payload.macAddress(), status);
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
                            log.info("MQTT로 발견된 디바이스를 저장했습니다. mac={}, ip={}, status={}", payload.macAddress(), payload.ip(), status);
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
                    log.warn("start time이 없어 packet_meta를 건너뜁니다. raw={}", line);
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
                log.warn("flow packet 파싱에 실패했습니다. 건너뜁니다. raw={}", line, ex);
            }
        }

        if (!entities.isEmpty()) {
            List<PacketMeta> saved = packetMetaRepository.saveAll(entities);
            log.info("MQTT에서 받은 packet_meta {}건을 저장했습니다.", saved.size());

            // ML 결과가 오지 않더라도 외부 IP 접근은 즉시 이상치로 기록한다.
            saved.forEach(this::markExternalAccessIfNeeded);

            mlRequestPublisher.publishPacketMetaJsonl(saved);
        }
    }

    private void markExternalAccessIfNeeded(PacketMeta meta) {
        String externalIp = findExternalIp(meta);
        if (externalIp == null) {
            return;
        }
        AnomalyScore score = anomalyScoreRepository.findByPacketMeta(meta.getPacketMetaId())
                .orElseGet(() -> AnomalyScore.builder()
                        .packetMeta(meta.getPacketMetaId())
                        .ts(meta.getEndTime() != null ? meta.getEndTime() : meta.getStartTime())
                        .build());
        score.setIsAnom(true);
        score = anomalyScoreRepository.save(score);

        OffsetDateTime eventTs = Optional.ofNullable(score.getTs()).orElse(OffsetDateTime.now());
        OffsetDateTime lastNormalTs = anomalyScoreRepository.findLastNormalTimestampBefore(eventTs);
        OffsetDateTime lastAlertTs = alertRepository.findLatestAlertTimestampBefore(eventTs);
        OffsetDateTime baselineTs = lastNormalTs != null
                ? lastNormalTs.plusNanos(1)
                : OffsetDateTime.of(1970, 1, 1, 0, 0, 0, 0, ZoneOffset.UTC);

        List<AnomalyScore> recent = anomalyScoreRepository.findTop3ByIsAnomTrueAndTsBetweenOrderByTsDescScoreIdDesc(
                baselineTs,
                eventTs
        );
        boolean threeConsecutive = recent.size() >= 3;
        boolean alreadyAlertedInRun = lastAlertTs != null && !lastAlertTs.isBefore(baselineTs);

        if (!threeConsecutive || alreadyAlertedInRun) {
            log.info("외부 접근 알림 생성을 건너뜁니다. threeConsecutive={}, alreadyAlertedInRun={}, lastNormalTs={}, lastAlertTs={}",
                    threeConsecutive, alreadyAlertedInRun, lastNormalTs, lastAlertTs);
            return;
        }

        createExternalAccessAlert(meta, score, externalIp);
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
            log.warn("시간 파싱에 실패했습니다: {}", isoTime);
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

    private String findExternalIp(PacketMeta packetMeta) {
        String src = packetMeta.getSrcIp();
        if (StringUtils.hasText(src) && !isInternalIp(src)) {
            return src;
        }
        String dst = packetMeta.getDstIp();
        if (StringUtils.hasText(dst) && !isInternalIp(dst)) {
            return dst;
        }
        return null;
    }

    private boolean isInternalIp(String ip) {
        String prefix = extractPrefix(ip);
        if (prefix == null) {
            return false;
        }
        return deviceRepository.findAll().stream()
                .map(Device::getIp)
                .filter(StringUtils::hasText)
                .map(this::extractPrefix)
                .anyMatch(prefix::equals);
    }

    private String extractPrefix(String ip) {
        if (!StringUtils.hasText(ip)) {
            return null;
        }
        String[] parts = ip.split("\\.");
        if (parts.length < 2) {
            return null;
        }
        return parts[0] + "." + parts[1];
    }

    private void createExternalAccessAlert(PacketMeta meta, AnomalyScore score, String externalIp) {
        // 이미 알림이 연결되어 있으면 중복 생성하지 않는다.
        if (score.getAlert() != null && alertRepository.findById(score.getAlert()).isPresent()) {
            return;
        }

        Device device = resolveDeviceByIp(meta);
        OffsetDateTime ts = meta.getEndTime() != null ? meta.getEndTime() : meta.getStartTime();
        String evidence = String.format(
                "{\"message\":\"외부 IP(%s)가 접근했습니다.\",\"srcIp\":\"%s\",\"dstIp\":\"%s\"}",
                externalIp,
                meta.getSrcIp(),
                meta.getDstIp()
        );

        Alert alert = Alert.builder()
                .ts(ts != null ? ts : OffsetDateTime.now())
                .device(device)
                .severity("HIGH")
                .reason("외부 접근 감지")
                .evidence(evidence)
                .status("NEW")
                .build();
        Alert savedAlert = alertRepository.save(alert);
        savedAlert.setAnomalyScore(score);
        alertRepository.save(savedAlert);
        anomalyScoreRepository.save(score);

        if (device != null) {
            userDeviceRepository.findAllByDeviceDeviceId(device.getDeviceId())
                    .forEach(userDevice -> {
                        UserAlert userAlert = userAlertRepository.save(UserAlert.create(
                                userDevice.getUser(),
                                savedAlert,
                                ts != null ? ts : OffsetDateTime.now(),
                                false,
                                "IN_APP",
                                "PENDING"
                        ));
                        dashboardService.sendAlertToUser(userAlert);
                    });
        }
    }

    private Device resolveDeviceByIp(PacketMeta packetMeta) {
        if (packetMeta == null) {
            return null;
        }
        if (StringUtils.hasText(packetMeta.getSrcIp())) {
            Device bySrc = deviceRepository.findFirstByIp(packetMeta.getSrcIp()).orElse(null);
            if (bySrc != null) {
                return bySrc;
            }
        }
        if (StringUtils.hasText(packetMeta.getDstIp())) {
            return deviceRepository.findFirstByIp(packetMeta.getDstIp()).orElse(null);
        }
        return null;
    }
}
