package com.example.demo.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "twin_residuals")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TwinResidual {

    @Id
    @GeneratedValue(generator = "uuid2")
    @Column(name = "residual_id")
    private UUID residualId;

    private OffsetDateTime ts;

    @Column(name = "flow_id")
    private UUID flow;

    @Column(name = "twin_ver")
    private String twinVer;

    private Double pred;
    private Double actual;
    private Double residual;

    private String state;
}
