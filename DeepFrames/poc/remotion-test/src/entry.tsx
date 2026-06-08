import React from "react";
import { Composition } from "remotion";
import { TestScene } from "./Scene";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="TestScene"
        component={TestScene}
        durationInFrames={60}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
