"use strict";
var _InCallManager = require("react-native").NativeModules.InCallManager;
import { Platform } from "react-native";

class InCallManager {
  constructor() {
    this.vibrate = false;
  }

  start(setup) {
    setup = setup === undefined ? {} : setup;
    let auto = setup.auto === false ? false : true;
    let media = setup.media === "video" ? "video" : "audio";
    _InCallManager.start(media, auto);
  }

  stop() {
    _InCallManager.stop();
  }

  async getIsWiredHeadsetPluggedIn() {
    let isPluggedIn = await _InCallManager.getIsWiredHeadsetPluggedIn();
    return { isWiredHeadsetPluggedIn: isPluggedIn };
  }

  setKeepScreenOn(enable) {
    enable = enable === true ? true : false;
    _InCallManager.setKeepScreenOn(enable);
  }

  setSpeakerphoneOn(enable) {
    enable = enable === true ? true : false;
    _InCallManager.setSpeakerphoneOn(enable);
  }

  setForceSpeakerphoneOn(_flag) {
    let flag = typeof _flag === "boolean" ? (_flag ? 1 : -1) : 0;
    _InCallManager.setForceSpeakerphoneOn(flag);
  }

  //Android only
  async chooseAudioRoute(route) {
    let result = await _InCallManager.chooseAudioRoute(route);
    return result;
  }

  async requestAudioFocus() {
    if (Platform.OS === "android") {
      return await _InCallManager.requestAudioFocusJS();
    } else {
      console.log("ios doesn't support requestAudioFocus()");
    }
  }

  async abandonAudioFocus() {
    if (Platform.OS === "android") {
      return await _InCallManager.abandonAudioFocusJS();
    } else {
      console.log("ios doesn't support requestAudioFocus()");
    }
  }
}

export default new InCallManager();
