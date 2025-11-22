package com.example.demo.domain;

import com.example.demo.exception.AccessDeniedException;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "user_alerts")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class UserAlert {

    @Id
    @Column(name = "user_alert_id")
    @GeneratedValue(generator = "uuid2")
    private UUID userAlertId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "alert_id")
    private Alert alert;

    @Column(name = "notified_at")
    private OffsetDateTime notifiedAt;

    @Column(name = "is_read")
    private Boolean isRead;

    private String channel;

    @Column(name = "delivery_status")
    private String deliveryStatus;

    public static UserAlert create(
            User user,
            Alert alert,
            OffsetDateTime notifiedAt,
            Boolean isRead,
            String channel,
            String deliveryStatus
    ) {
        UserAlert userAlert = new UserAlert();
        userAlert.user = user;
        userAlert.alert = alert;
        userAlert.notifiedAt = notifiedAt;
        userAlert.isRead = isRead;
        userAlert.channel = channel;
        userAlert.deliveryStatus = deliveryStatus;
        return userAlert;
    }

    public void markAsRead() {
        this.isRead = true;
    }

    public void updateDeliveryStatus(String deliveryStatus) {
        this.deliveryStatus = deliveryStatus;
    }

    public void ensureUser(UUID userId) {
        if (user == null || user.getUserId() == null || !user.getUserId().equals(userId)) {
            throw new AccessDeniedException("해당 알림은 사용자 " + userId + "의 것이 아닙니다.");
        }
    }
}
