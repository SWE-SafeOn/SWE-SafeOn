package com.example.demo.dto.dashboard;

import com.example.demo.domain.UserDevice;
import lombok.Builder;

@Builder
public record DashboardDeviceDto(
        String id,
        String vendor,
        String ip,
        String macAddr,
        Boolean discovered,
        String createdAt,
        String linkedAt,
        String label
) {
    public static DashboardDeviceDto from(UserDevice userDevice) {
        var device = userDevice.getDevice();
        return DashboardDeviceDto.builder()
                .id(device.getDeviceId() != null ? device.getDeviceId().toString() : null)
                .vendor(device.getVendor())
                .ip(device.getIp())
                .macAddr(device.getMacAddr())
                .discovered(device.getDiscovered())
                .createdAt(device.getCreatedAt() != null ? device.getCreatedAt().toString() : null)
                .linkedAt(userDevice.getLinkedAt() != null ? userDevice.getLinkedAt().toString() : null)
                .label(userDevice.getLabel())
                .build();
    }
}
