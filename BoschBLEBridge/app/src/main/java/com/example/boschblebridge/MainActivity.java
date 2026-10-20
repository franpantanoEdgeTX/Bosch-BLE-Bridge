package com.example.boschblebridge;

import android.Manifest;
import android.app.*;
import android.os.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.view.*;
import android.widget.*;
import java.net.*;
import java.io.*;
import java.util.*;

public class MainActivity extends Activity {
 BluetoothAdapter adapter; BluetoothLeScanner scanner; BluetoothGatt gatt;
 TextView log; LinearLayout devices; EditText port; final Handler handler=new Handler();
 final Set<String> seen=new HashSet<>(); boolean scanning=false;
 final UUID CCC=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
 final Queue<BluetoothGattDescriptor> queue=new ArrayDeque<>();
 void say(String s){runOnUiThread(()->{log.append(s+"\n");});}
 void send(String s){new Thread(()->{try(Socket sock=new Socket("127.0.0.1",Integer.parseInt(port.getText().toString()))){PrintWriter out=new PrintWriter(new OutputStreamWriter(sock.getOutputStream()),true);out.println(s);}catch(Exception e){say("TCP: "+e.getMessage());}}).start();}
 String hex(byte[] b){StringBuilder x=new StringBuilder(); for(byte a:b)x.append(String.format(java.util.Locale.US,"%02X",a&255));return x.toString();}
 @Override public void onCreate(Bundle b){super.onCreate(b);
  LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setPadding(12,12,12,12);
  TextView title=new TextView(this);title.setText("Bosch BLE -> AndroWish (TCP local)");title.setTextSize(19);root.addView(title);
  port=new EditText(this);port.setInputType(2);port.setText("8765");root.addView(port);
  Button scan=new Button(this);scan.setText("Buscar BLE (10 segundos)");root.addView(scan);
  ScrollView dv=new ScrollView(this);devices=new LinearLayout(this);devices.setOrientation(1);dv.addView(devices);root.addView(dv,new LinearLayout.LayoutParams(-1,0,1));
  ScrollView sv=new ScrollView(this);log=new TextView(this);sv.addView(log);root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
  BluetoothManager mgr=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);adapter=mgr.getAdapter();
  scan.setOnClickListener(v->startScan());say("Primero iniciar receptor TCP en AndroWish. Luego buscar y elegir medidor.");
  if(Build.VERSION.SDK_INT>=31 && (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)!=PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED))requestPermissions(new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT},1);
  else if(Build.VERSION.SDK_INT<31 && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION},1);
 }
 ScanCallback callback=new ScanCallback(){@Override public void onScanResult(int type,ScanResult r){BluetoothDevice d=r.getDevice();String addr=d.getAddress();if(!seen.add(addr))return;String name="(sin nombre)";try{if(d.getName()!=null)name=d.getName();}catch(SecurityException e){}String label=name+"  "+addr;runOnUiThread(()->{Button b=new Button(MainActivity.this);b.setText(label);devices.addView(b);b.setOnClickListener(v->connect(d));});}};
 void startScan(){if(adapter==null || !adapter.isEnabled()){say("Activa Bluetooth en Android");return;}try{scanner=adapter.getBluetoothLeScanner();seen.clear();devices.removeAllViews();scanner.startScan(callback);scanning=true;say("Escaneando...");handler.postDelayed(()->stopScan(),10000);}catch(Exception e){say("Scan: "+e);}}
 void stopScan(){if(scanning){try{scanner.stopScan(callback);}catch(Exception e){}scanning=false;say("Fin escaneo");}}
 void connect(BluetoothDevice d){stopScan();if(gatt!=null){gatt.close();gatt=null;}say("Conectando "+d.getAddress());try{gatt=d.connectGatt(this,false,gattCb,BluetoothDevice.TRANSPORT_LE);}catch(Exception e){say("Conectar: "+e);}}
 BluetoothGattCallback gattCb=new BluetoothGattCallback(){
  @Override public void onConnectionStateChange(BluetoothGatt g,int status,int state){say("GATT estado="+state+" status="+status);if(state==BluetoothProfile.STATE_CONNECTED)g.discoverServices();}
  @Override public void onServicesDiscovered(BluetoothGatt g,int status){say("Servicios descubiertos status="+status);queue.clear();for(BluetoothGattService s:g.getServices()){say("SERVICIO "+s.getUuid());for(BluetoothGattCharacteristic c:s.getCharacteristics()){int p=c.getProperties();say("  CHAR "+c.getUuid()+" props="+p);if((p & (BluetoothGattCharacteristic.PROPERTY_NOTIFY|BluetoothGattCharacteristic.PROPERTY_INDICATE))!=0){g.setCharacteristicNotification(c,true);BluetoothGattDescriptor desc=c.getDescriptor(CCC);if(desc!=null){desc.setValue((p & BluetoothGattCharacteristic.PROPERTY_NOTIFY)!=0?BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE:BluetoothGattDescriptor.ENABLE_INDICATION_VALUE);queue.add(desc);}}}}nextDesc(g);}
  @Override public void onDescriptorWrite(BluetoothGatt g,BluetoothGattDescriptor d,int status){say("Suscripcion "+d.getCharacteristic().getUuid()+" status="+status);nextDesc(g);}
  @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c){byte[] v=c.getValue();got(c,v);}
  @Override public void onCharacteristicRead(BluetoothGatt g,BluetoothGattCharacteristic c,int status){if(status==0)got(c,c.getValue());}
 };
 void nextDesc(BluetoothGatt g){BluetoothGattDescriptor d=queue.poll();if(d!=null){try{if(!g.writeDescriptor(d))nextDesc(g);}catch(Exception e){say("Descriptor: "+e);nextDesc(g);}}}
 void got(BluetoothGattCharacteristic c,byte[] bytes){String data=hex(bytes);say("RX "+c.getUuid()+" "+data);send("HEX:"+data);}
 @Override protected void onDestroy(){stopScan();if(gatt!=null){gatt.disconnect();gatt.close();}super.onDestroy();}
}
