package com.example.demo.dto.alert;

import com.example.demo.domain.Alert;
import com.example.demo.domain.UserAlert;
import lombok.Builder;

@Builder
public record AlertResponseDto(
        String id,
        String userId,
        String deviceId,
        String severity,
        String reason,
        String evidence,
        String timestamp,
        String status,
        Boolean read,
        String deliveryStatus
) {

    public static AlertResponseDto from(UserAlert userAlert) {
        return from(userAlert.getAlert(),
                userAlert.getUser() != null ? userAlert.getUser().getUserId().toString() : null,
                userAlert.getIsRead(),
                userAlert.getDeliveryStatus());
    }

    private static AlertResponseDto from(Alert alert, String userId, Boolean read, String deliveryStatus) {
        return AlertResponseDto.builder()
                .id(alert.getAlertId() != null ? alert.getAlertId().toString() : null)
                .userId(userId)
                .deviceId(alert.getDevice() != null && alert.getDevice().getDeviceId() != null
                        ? alert.getDevice().getDeviceId().toString()
                        : null)
                .severity(alert.getSeverity())
                .reason(alert.getReason())
                .evidence(alert.getEvidence())
                .timestamp(alert.getTs() != null ? alert.getTs().toString() : null)
                .status(alert.getStatus())
                .read(read)
                .deliveryStatus(deliveryStatus)
                .build();
    }
}
