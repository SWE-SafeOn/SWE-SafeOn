package com.example.demo.mqtt;

import com.example.demo.config.MlMqttProperties;
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
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class MlResultMqttListener implements MqttPacketListener {

    private static final String DEFAULT_SEVERITY = "HIGH";
    private static final String DEFAULT_REASON = "Anomaly detected by ML";
    private static final String DEFAULT_STATUS = "NEW";
    private static final String DEFAULT_CHANNEL = "IN_APP";
    private static final String DEFAULT_DELIVERY_STATUS = "PENDING";

    private final MlMqttProperties mqttProperties;
    private final ObjectMapper objectMapper;
    private final AnomalyScoreRepository anomalyScoreRepository;
    private final PacketMetaRepository packetMetaRepository;
    private final AlertRepository alertRepository;
    private final DeviceRepository deviceRepository;
    private final UserDeviceRepository userDeviceRepository;
    private final UserAlertRepository userAlertRepository;
    private final DashboardService dashboardService;

    @Override
    @Transactional
    public void onPacketReceived(String topic, byte[] payload) {
        if (!matches(topic, mqttProperties.getMlResultTopic())) {
            return;
        }
        String message = new String(payload, StandardCharsets.UTF_8);
        try {
            MlResultPayload result = objectMapper.readValue(message, MlResultPayload.class);
            processResult(result);
        } catch (Exception ex) {
            log.warn("ML 결과 페이로드 처리에 실패했습니다. topic={}, payload={}", topic, message, ex);
        }
    }

    private boolean matches(String topic, String expected) {
        return StringUtils.hasText(expected) && expected.equals(topic);
    }

    /**
     * @param payload
     */
    private void processResult(MlResultPayload payload) {
        if (payload.packetMetaId() == null) {
            log.warn("packetMetaId가 없어 ML 결과를 건너뜁니다: {}", payload);
            return;
        }
        PacketMeta packetMeta = packetMetaRepository.findById(payload.packetMetaId()).orElse(null);
        if (packetMeta == null) {
            log.warn("알 수 없는 packetMetaId={}로 ML 결과를 건너뜁니다", payload.packetMetaId());
            return;
        }

        OffsetDateTime ts = resolveTime(payload.timestamp());
        OffsetDateTime eventTs = ts != null ? ts : OffsetDateTime.now();

        String externalIp = findExternalIp(packetMeta);
        boolean isExternalAccess = StringUtils.hasText(externalIp);
        boolean isAnomaly = Boolean.TRUE.equals(payload.isAnom()) || isExternalAccess;

        AnomalyScore score = anomalyScoreRepository.findByPacketMeta(payload.packetMetaId()).orElse(
                AnomalyScore.builder().packetMeta(payload.packetMetaId()).build()
        );
        score.setTs(eventTs);
        score.setIsoScore(payload.isoScore());
        score.setRfScore(payload.rfScore());
        score.setHybridScore(payload.hybridScore());
        score.setIsAnom(isAnomaly);
        score = anomalyScoreRepository.save(score);

        if (!isAnomaly) {
            return;
        }

        OffsetDateTime lastNormalTs = anomalyScoreRepository.findLastNormalTimestampBefore(eventTs);
        OffsetDateTime lastAlertTs = alertRepository.findLatestAlertTimestampBefore(eventTs);
        OffsetDateTime baselineTs = lastNormalTs != null
                // 바로 직전 정상 이후부터만 집계해 동일 타임스탬프의 정상값을 포함하지 않는다.
                ? lastNormalTs.plusNanos(1)
                : OffsetDateTime.of(1970, 1, 1, 0, 0, 0, 0, ZoneOffset.UTC);
        boolean alreadyAlertedInRun = lastAlertTs != null && !lastAlertTs.isBefore(baselineTs);

        // 정상 이후 구간에서 isAnom=true인 점수만으로 연속 3회 여부를 판단한다.
        List<AnomalyScore> recent = anomalyScoreRepository.findTop3ByIsAnomTrueAndTsBetweenOrderByTsDescScoreIdDesc(
                baselineTs,
                eventTs
        );
        boolean threeConsecutive = recent.size() >= 3;

        if (!threeConsecutive || alreadyAlertedInRun) {
            log.info("알림 생성을 건너뜁니다. threeConsecutive={}, alreadyAlertedInRun={}, lastNormalTs={}, lastAlertTs={}",
                    threeConsecutive, alreadyAlertedInRun, lastNormalTs, lastAlertTs);
            return;
        }

        Device device = resolveDevice(payload.deviceId(), packetMeta);
        String alertReason = StringUtils.hasText(payload.reason()) ? payload.reason() : DEFAULT_REASON;
        String alertEvidence = payload.evidence();

        if (isExternalAccess) {
            alertReason = "외부 접근 감지";
            alertEvidence = String.format(
                    "{\"message\":\"외부 IP(%s)가 접근했습니다.\",\"srcIp\":\"%s\",\"dstIp\":\"%s\"}",
                    externalIp,
                    packetMeta.getSrcIp(),
                    packetMeta.getDstIp()
            );
            log.warn("외부 접근이 감지되었습니다. externalIp={}, packetMetaId={}, srcIp={}, dstIp={}",
                    externalIp, packetMeta.getPacketMetaId(), packetMeta.getSrcIp(), packetMeta.getDstIp());
        }

        Alert alert = Alert.builder()
                .ts(eventTs)
                .device(device)
                .severity(StringUtils.hasText(payload.severity()) ? payload.severity() : DEFAULT_SEVERITY)
                .reason(alertReason)
                .evidence(alertEvidence)
                .status(DEFAULT_STATUS)
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
                                DEFAULT_CHANNEL,
                                DEFAULT_DELIVERY_STATUS
                        ));
                        dashboardService.sendAlertToUser(userAlert);
                    });
        }
    }

    private Device resolveDevice(UUID deviceId) {
        if (deviceId == null) {
            return null;
        }
        Optional<Device> device = deviceRepository.findById(deviceId);
        if (device.isEmpty()) {
            log.warn("ML 결과에 알 수 없는 deviceId={}가 포함되어 있습니다", deviceId);
        }
        return device.orElse(null);
    }

    private Device resolveDevice(UUID deviceId, PacketMeta packetMeta) {
        Device fromId = resolveDevice(deviceId);
        if (fromId != null) {
            return fromId;
        }

        if (packetMeta == null) {
            return null;
        }

        if (StringUtils.hasText(packetMeta.getSrcIp())) {
            Optional<Device> bySrc = deviceRepository.findFirstByIp(packetMeta.getSrcIp());
            if (bySrc.isPresent()) {
                return bySrc.get();
            }
        }
        if (StringUtils.hasText(packetMeta.getDstIp())) {
            Optional<Device> byDst = deviceRepository.findFirstByIp(packetMeta.getDstIp());
            if (byDst.isPresent()) {
                return byDst.get();
            }
        }

        log.warn("packetMetaId={}에 대한 디바이스를 찾을 수 없습니다 (srcIp={}, dstIp={})",
                packetMeta.getPacketMetaId(), packetMeta.getSrcIp(), packetMeta.getDstIp());
        return null;
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
            log.warn("ML 결과의 timestamp를 파싱할 수 없습니다: {}", isoTime);
            return null;
        }
    }

    private record MlResultPayload(
            @JsonAlias({"packet_meta_id", "packetMetaId"}) UUID packetMetaId,
            @JsonAlias({"device_id", "deviceId"}) UUID deviceId,
            @JsonAlias({"iso_score", "isoScore"}) Double isoScore,
            @JsonAlias({"rf_score", "rfScore"}) Double rfScore,
            @JsonAlias({"hybrid_score", "hybridScore"}) Double hybridScore,
            @JsonAlias({"is_anom", "isAnom"}) Boolean isAnom,
            @JsonAlias({"severity"}) String severity,
            @JsonAlias({"reason"}) String reason,
            @JsonAlias({"evidence"}) String evidence,
            @JsonAlias({"ts", "timestamp"}) String timestamp
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
}
