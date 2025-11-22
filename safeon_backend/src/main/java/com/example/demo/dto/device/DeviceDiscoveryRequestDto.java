package com.example.demo.dto.device;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class DeviceDiscoveryRequestDto {

    @NotBlank
    private String vendor;

    private String ip;

    @NotBlank
    private String macAddr;

    public DeviceDiscoveryRequestDto(String vendor, String ip, String macAddr) {
        this.vendor = vendor;
        this.ip = ip;
        this.macAddr = macAddr;
    }
}
