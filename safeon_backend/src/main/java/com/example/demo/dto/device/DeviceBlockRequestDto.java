package com.example.demo.dto.device;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class DeviceBlockRequestDto {

    @NotBlank(message = "deviceId is required")
    private String deviceId;

    @NotBlank(message = "macAddress is required")
    private String macAddress;

    private String ip;
    private String name;
}
