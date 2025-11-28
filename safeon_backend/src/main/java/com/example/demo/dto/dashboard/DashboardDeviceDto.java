package com.example.demo.dto.dashboard;

import com.example.demo.domain.UserDevice;
import lombok.Builder;

@Builder
public record DashboardDeviceDto(
        String id,
        String name,
        String ip,
        Boolean discovered,
        String status,
        String createdAt,
        String linkedAt
) {
    public static DashboardDeviceDto from(UserDevice userDevice) {
        var device = userDevice.getDevice();
        return DashboardDeviceDto.builder()
                .id(device.getDeviceId() != null ? device.getDeviceId().toString() : null)
                .name(device.getName())
                .ip(device.getIp())
                .discovered(device.getDiscovered())
                .status(device.getStatus())
                .createdAt(device.getCreatedAt() != null ? device.getCreatedAt().toString() : null)
                .linkedAt(userDevice.getLinkedAt() != null ? userDevice.getLinkedAt().toString() : null)
                .build();
    }
}
