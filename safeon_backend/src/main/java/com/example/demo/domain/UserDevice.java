package com.example.demo.domain;

import com.example.demo.exception.AccessDeniedException;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "user_devices")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class UserDevice {

    @Id
    @Column(name = "user_device_id")
    @GeneratedValue(generator = "uuid2")
    private UUID userDeviceId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "device_id")
    private Device device;

    private String label;

    @Column(name = "linked_at")
    private OffsetDateTime linkedAt;

    public static UserDevice create(User user, Device device, String label, OffsetDateTime linkedAt) {
        UserDevice userDevice = new UserDevice();
        userDevice.user = user;
        userDevice.device = device;
        userDevice.label = label;
        userDevice.linkedAt = linkedAt;
        return userDevice;
    }

    public void updateLabel(String label) {
        this.label = label;
    }

    public void ensureOwner(UUID userId) {
        if (user == null || user.getUserId() == null || !user.getUserId().equals(userId)) {
            throw new AccessDeniedException("해당 디바이스는 사용자 " + userId + "의 소유가 아닙니다.");
        }
    }
}
