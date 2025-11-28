package com.example.demo.dto.dashboard;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.time.LocalDate;

@Getter
@RequiredArgsConstructor
public class DailyAnomalyCountDto {
    private final LocalDate date;
    private final Long count;
}
