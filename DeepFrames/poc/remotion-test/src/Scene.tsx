import React from "react";
import { useCurrentFrame, useVideoConfig, AbsoluteFill, interpolate } from "remotion";

export const TestScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();

  // Simple animation: a colored box moving across the screen
  const progress = interpolate(frame, [0, durationInFrames - 1], [0, 1]);
  const x = interpolate(progress, [0, 1], [100, 1720]);
  const opacity = interpolate(frame, [0, 10], [0, 1], { extrapolateRight: "clamp" });
  const rotation = interpolate(frame, [0, durationInFrames], [0, 360]);

  return (
    <AbsoluteFill style={{ backgroundColor: "#1a1a2e" }}>
      <div
        style={{
          position: "absolute",
          left: x,
          top: 440,
          width: 200,
          height: 200,
          backgroundColor: "#e94560",
          borderRadius: 20,
          opacity,
          transform: `rotate(${rotation}deg)`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 48,
          color: "white",
          fontWeight: "bold",
          fontFamily: "Arial, sans-serif",
        }}
      >
        {frame}
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 60,
          left: 0,
          right: 0,
          textAlign: "center",
          fontSize: 24,
          color: "#aaa",
          fontFamily: "Arial, sans-serif",
        }}
      >
        DeepFrames POC 3a — Remotion Render Test ({fps}fps, frame {frame}/{durationInFrames})
      </div>
    </AbsoluteFill>
  );
};
