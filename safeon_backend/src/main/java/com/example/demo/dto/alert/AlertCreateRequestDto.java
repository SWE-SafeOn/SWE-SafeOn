package com.example.demo.dto.alert;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;

@Getter
public class AlertCreateRequestDto {

    @NotBlank
    private String deviceId;

    @NotBlank
    private String severity;

    @NotBlank
    private String reason;

    private String evidence;

    private String status;

    private String channel;
}
