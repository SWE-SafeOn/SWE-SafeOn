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

    private String status;

    public DeviceDiscoveryRequestDto(String name, String ip, String macAddress) {
        this(name, ip, macAddress, "connect");
    }

    public DeviceDiscoveryRequestDto(String name, String ip, String macAddress, String status) {
        this.macAddress = macAddress;
        this.name = name;
        this.ip = ip;
        this.status = status;
    }
}
