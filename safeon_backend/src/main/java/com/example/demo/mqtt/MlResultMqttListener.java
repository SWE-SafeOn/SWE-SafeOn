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
import java.util.Optional;
import java.util.UUID;

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
            log.warn("Failed to process ML result payload. topic={}, payload={}", topic, message, ex);
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
            log.warn("Skip ML result without packetMetaId: {}", payload);
            return;
        }
        PacketMeta packetMeta = packetMetaRepository.findById(payload.packetMetaId()).orElse(null);
        if (packetMeta == null) {
            log.warn("Skip ML result with unknown packetMetaId={}", payload.packetMetaId());
            return;
        }

        OffsetDateTime ts = resolveTime(payload.timestamp());

        AnomalyScore score = AnomalyScore.builder()
                .ts(ts != null ? ts : OffsetDateTime.now())
                .packetMeta(payload.packetMetaId())
                .isoScore(payload.isoScore())
                .aeScore(payload.aeScore())
                .gbmScore(payload.gbmScore())
                .hybridScore(payload.hybridScore())
                .isAnom(Boolean.TRUE.equals(payload.isAnom()))
                .build();
        score = anomalyScoreRepository.save(score);

        if (!Boolean.TRUE.equals(payload.isAnom())) {
            return;
        }

        Device device = resolveDevice(payload.deviceId(), packetMeta);
        Alert alert = Alert.builder()
                .ts(ts != null ? ts : OffsetDateTime.now())
                .device(device)
                .severity(StringUtils.hasText(payload.severity()) ? payload.severity() : DEFAULT_SEVERITY)
                .reason(StringUtils.hasText(payload.reason()) ? payload.reason() : DEFAULT_REASON)
                .evidence(payload.evidence())
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
            log.warn("ML result includes unknown deviceId={}", deviceId);
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

        log.warn("Cannot resolve device for packetMetaId={} (srcIp={}, dstIp={})",
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
            log.warn("Cannot parse ML result timestamp: {}", isoTime);
            return null;
        }
    }

    private record MlResultPayload(
            @JsonAlias({"packet_meta_id", "packetMetaId"}) UUID packetMetaId,
            @JsonAlias({"device_id", "deviceId"}) UUID deviceId,
            @JsonAlias({"iso_score", "isoScore"}) Double isoScore,
            @JsonAlias({"ae_score", "aeScore"}) Double aeScore,
            @JsonAlias({"gbm_score", "gbmScore"}) Double gbmScore,
            @JsonAlias({"hybrid_score", "hybridScore"}) Double hybridScore,
            @JsonAlias({"is_anom", "isAnom"}) Boolean isAnom,
            @JsonAlias({"severity"}) String severity,
            @JsonAlias({"reason"}) String reason,
            @JsonAlias({"evidence"}) String evidence,
            @JsonAlias({"ts", "timestamp"}) String timestamp
    ) {
    }
}
