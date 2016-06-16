/*
       Licensed to the Apache Software Foundation (ASF) under one
       or more contributor license agreements.  See the NOTICE file
       distributed with this work for additional information
       regarding copyright ownership.  The ASF licenses this file
       to you under the Apache License, Version 2.0 (the
       "License"); you may not use this file except in compliance
       with the License.  You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing,
       software distributed under the License is distributed on an
       "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
       KIND, either express or implied.  See the License for the
       specific language governing permissions and limitations
       under the License.
*/
package uk.co.onefile.nomadionic.audiocapture;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

import android.os.Build;
import android.util.Log;
import android.content.Context;
import android.content.Intent;

import org.apache.cordova.file.FileUtils;
import org.apache.cordova.file.LocalFilesystemURL;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.Config;
import org.apache.cordova.CordovaArgs;
import org.apache.cordova.CordovaHttpAuthHandler;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.LOG;
import org.apache.cordova.PluginManager;
import org.apache.cordova.PluginResult;

import org.json.JSONException;
import org.json.JSONObject;

import android.Manifest;
import android.app.Activity;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;

public class AudioRecorder extends AppCompatActivity {
	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Log.i("MyNewActivityGap","MyNewActivityGap - OnCreate()");
	}
}

public class CDVAudioRecorder extends CordovaPlugin {

	@Override
	protected void pluginInitialize() {
		super.pluginInitialize();
		Log.i("CDVAudioRecorder","pluginInitialize()");
	}

	@Override
	public boolean execute(String action, CordovaArgs args, final CallbackContext callbackContext) throws JSONException {
		Log.i("CDVAudioRecorder", "execute() called - checking action equals audioRecorder");
		Log.i("CDVAudioRecorder", action);
		if (action.equals("audioRecorder")) {
			cordova.getActivity().runOnUiThread(new Runnable() {
				@Override
				public void run() {
					Context context = cordova.getActivity().getApplicationContext();
					Intent intent = new Intent(context, AudioRecorder.class);
					cordova.getActivity().startActivity(intent);
					Log.i("CDVAudioRecorder","executing run()");
				}
			});
			Log.i("CDVAudioRecorder", "returning true");
			return true;
		}
		Log.i("CDVAudioRecorder", "action not equal to audioRecorder - finishing");
	}
}
