# Ambient response adjustment (0.1.112)

User found 0.1.111's 15–30 second stable polling too slow. Keep adaptive sampling
but use 2 / 3 / 5 seconds instead of 5 / 15 / 30. Initial sampling and recovery
after detected changes or invalid data use two seconds. Timer tolerance is now
10% capped at 0.5 seconds. Detection can still wait until the next scheduled
sample, approximately five seconds in stable conditions plus tolerance and system
scheduling; this is not an immediate hardware-event subscription.

The continuous 6–180 nits brightness curve and 24-step, approximately one-second
linear fade remain unchanged. Diagnostic batching, disabled detailed release logs,
20-second marquee idle, charging eligibility and pixel protection are unchanged.
Polling work increases relative to 0.1.111; net power savings remain unmeasured.
Shared policy tests now verify the shorter intervals with the same drift and
invalid-sample scenarios.
