package com.example.demo.dto.device;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class DeviceDiscoveryRequestDto {

    @NotBlank
    private String macAddress;

    @NotBlank
    private String name;

    @NotBlank
    private String ip;

    public DeviceDiscoveryRequestDto(String name, String ip, String macAddress) {
        this.macAddress = macAddress;
        this.name = name;
        this.ip = ip;
    }
}
