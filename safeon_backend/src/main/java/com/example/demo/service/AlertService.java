package com.example.demo.service;

import com.example.demo.domain.Alert;
import com.example.demo.domain.Device;
import com.example.demo.domain.User;
import com.example.demo.domain.UserAlert;
import com.example.demo.dto.alert.AlertCreateRequestDto;
import com.example.demo.dto.alert.AlertResponseDto;
import com.example.demo.repository.DeviceRepository;
import com.example.demo.repository.AlertRepository;
import com.example.demo.repository.UserAlertRepository;
import com.example.demo.repository.UserRepository;
import com.example.demo.util.UuidParser;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class AlertService {

    private static final String STATUS_ACKNOWLEDGED = "ACKNOWLEDGED";
    private static final String STATUS_NEW = "NEW";
    private static final String DEFAULT_CHANNEL = "IN_APP";
    private static final String DEFAULT_DELIVERY_STATUS = "PENDING";

    private final UserRepository userRepository;
    private final DeviceRepository deviceRepository;
    private final AlertRepository alertRepository;
    private final UserAlertRepository userAlertRepository;
    private final DashboardService dashboardService;

    @Transactional(readOnly = true)
    public List<AlertResponseDto> getAlerts(UUID userId) {
        return userAlertRepository
                .findByUserUserIdOrderByNotifiedAtDesc(userId)
                .stream()
                .map(AlertResponseDto::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public AlertResponseDto getAlert(String alertId, UUID userId) {
        UUID alertUuid = UuidParser.parseUUID(alertId);
        UserAlert userAlert = userAlertRepository.getByUserUserIdAndAlertAlertId(userId, alertUuid);
        userAlert.ensureUser(userId);
        return AlertResponseDto.from(userAlert);
    }

    @Transactional
    public AlertResponseDto acknowledgeAlert(String alertId, UUID userId) {
        UUID alertUuid = UuidParser.parseUUID(alertId);
        UserAlert userAlert = userAlertRepository.getByUserUserIdAndAlertAlertId(userId, alertUuid);
        userAlert.ensureUser(userId);

        Alert alert = userAlert.getAlert();
        alert.updateStatus(STATUS_ACKNOWLEDGED);
        userAlert.markAsRead();
        userAlertRepository.save(userAlert);
        alertRepository.save(alert);
        dashboardService.sendAlertToUser(userAlert);

        return AlertResponseDto.from(userAlert);
    }

    @Transactional
    public AlertResponseDto createAlert(AlertCreateRequestDto request, UUID userId) {
        UUID deviceId = UuidParser.parseUUID(request.getDeviceId());
        Device device = deviceRepository.getByDeviceId(deviceId);
        User user = userRepository.getById(userId);

        OffsetDateTime now = OffsetDateTime.now();
        Alert alert = alertRepository.save(Alert.builder()
                .ts(now)
                .device(device)
                .severity(request.getSeverity())
                .reason(request.getReason())
                .evidence(request.getEvidence())
                .status(request.getStatus() != null ? request.getStatus() : STATUS_NEW)
                .build());

        UserAlert userAlert = userAlertRepository.save(
                UserAlert.create(
                        user,
                        alert,
                        now,
                        false,
                        request.getChannel() != null ? request.getChannel() : DEFAULT_CHANNEL,
                        DEFAULT_DELIVERY_STATUS
                )
        );
        dashboardService.sendAlertToUser(userAlert);
        return AlertResponseDto.from(userAlert);
    }
}
