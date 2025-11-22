package com.example.demo.service;

import com.example.demo.domain.Alert;
import com.example.demo.domain.UserAlert;
import com.example.demo.dto.alert.AlertResponseDto;
import com.example.demo.repository.AlertRepository;
import com.example.demo.repository.UserAlertRepository;
import com.example.demo.util.UuidParser;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class AlertService {

    private static final String STATUS_ACKNOWLEDGED = "ACKNOWLEDGED";

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
}
