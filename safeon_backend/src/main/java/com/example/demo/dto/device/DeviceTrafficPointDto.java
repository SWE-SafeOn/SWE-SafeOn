package com.example.demo.dto.device;

import com.example.demo.domain.PacketMeta;
import lombok.Builder;

import java.time.OffsetDateTime;

@Builder
public record DeviceTrafficPointDto(
        OffsetDateTime timestamp,
        Double pps,
        Double bps
) {

    public static DeviceTrafficPointDto from(PacketMeta meta) {
        return DeviceTrafficPointDto.builder()
                .timestamp(meta.getStartTime() != null ? meta.getStartTime() : meta.getEndTime())
                .pps(meta.getPps())
                .bps(meta.getBps())
                .build();
    }
}
