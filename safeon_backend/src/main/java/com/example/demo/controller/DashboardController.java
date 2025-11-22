package com.example.demo.controller;

import com.example.demo.dto.ApiResponseDto;
import com.example.demo.dto.dashboard.DashboardDeviceListResponseDto;
import com.example.demo.dto.dashboard.DashboardOverviewDto;
import com.example.demo.dto.dashboard.RecentAlertListResponseDto;
import com.example.demo.security.AuthenticatedUser;
import com.example.demo.service.DashboardService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequiredArgsConstructor
@RequestMapping("/dashboard")
public class DashboardController {

    private final DashboardService dashboardService;

    @GetMapping("/overview")
    public ResponseEntity<ApiResponseDto<DashboardOverviewDto>> getOverview(
            @AuthenticationPrincipal AuthenticatedUser currentUser
    ) {
        DashboardOverviewDto overview = dashboardService.getOverview(currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(overview));
    }

    @GetMapping("/devices")
    public ResponseEntity<ApiResponseDto<DashboardDeviceListResponseDto>> getDevices(
            @AuthenticationPrincipal AuthenticatedUser currentUser
    ) {
        DashboardDeviceListResponseDto devices = dashboardService.getDevices(currentUser.userId());
        return ResponseEntity.ok(ApiResponseDto.ok(devices));
    }

    @GetMapping("/alerts")
    public ResponseEntity<ApiResponseDto<RecentAlertListResponseDto>> getRecentAlerts(
            @AuthenticationPrincipal AuthenticatedUser currentUser,
            @RequestParam(required = false) Integer limit
    ) {
        RecentAlertListResponseDto alerts = dashboardService.getRecentAlerts(currentUser.userId(), limit);
        return ResponseEntity.ok(ApiResponseDto.ok(alerts));
    }

    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter stream(
            @AuthenticationPrincipal AuthenticatedUser currentUser
    ) {
        return dashboardService.stream(currentUser.userId());
    }
}
