package com.example.demo.dto.dashboard;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.List;

@Getter
@RequiredArgsConstructor
public class DailyAnomalyCountResponseDto {
    private final List<DailyAnomalyCountDto> data;
}
