package com.example.demo.dto.device;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class DeviceDiscoveryRequestDto {

    @NotBlank
    private String ip;

    public DeviceDiscoveryRequestDto(String ip) {
        this.ip = ip;
    }
}
