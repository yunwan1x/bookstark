package com.bookstark.bookstark_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Dedicated library images only. No content URI or user path crosses to Dart. */
class OwnedImagePickerChannel(private val activity: Activity, messenger: BinaryMessenger) {
 companion object {
  private val inboxLock=Any()
  // Per-process activity reconfiguration must not sweep another live channel's
  // copy or queued originals. Process death clears this registry naturally.
  private val activePaths=mutableSetOf<String>()
 }
 private val channel=MethodChannel(messenger,"bookstark/owned_image_picker")
 private val main=Handler(Looper.getMainLooper())
 private val worker=Executors.newSingleThreadExecutor()
 private val timer=Executors.newSingleThreadScheduledExecutor()
 private val ids=Regex("^[a-f0-9]{32}$")
 private val owners=mutableSetOf<String>()
 private val retired=mutableSetOf<String>()
 private val files=mutableMapOf<String,String>()
 private val ownedPaths=mutableMapOf<String,String>()
 @Volatile private var startupFailure=false
 private val requestCode=0x4262
 private val limit=64L*1024*1024
 private val batchLimit=256L*1024*1024
 private val reserve=128L*1024*1024
 private var pending:Job?=null
 private var pickerOpen=false
 private var disposed=false
 private class Job(val owner:String,val id:String,val reply:MethodChannel.Result){
  val signal=CancellationSignal()
  @Volatile var cancelled=false
  @Volatile var descriptor:android.content.res.AssetFileDescriptor?=null
  var copying=false
  fun cancel(){cancelled=true;signal.cancel();try{descriptor?.close()}catch(_:Exception){}}
 }
 init{
  worker.execute{try{sweepOrphans()}catch(_:Exception){startupFailure=true}}
  channel.setMethodCallHandler{call,reply->
   try{
    val owner=call.argument<String>("owner")?:throw IOException("Missing owner")
    if(!ids.matches(owner))throw IOException("Invalid owner")
    when(call.method){
     "registerOwner"->{
      // Serialized after the cold sweep; no picking before its outcome.
      worker.execute{
       main.post{
        if(startupFailure||disposed||retired.contains(owner)||owners.contains(owner)||owners.size>=32||retired.size>=4096)
         reply.error("image_inbox_cleanup_failed","Private image inbox requires cleanup",null)
        else{owners.add(owner);reply.success(mapOf("format" to 1,"owner" to owner,"registered" to true))}
       }
      }
     }
     "pick"->{
      val id=call.argument<String>("id")?:throw IOException("Missing operation")
      if(!ids.matches(id)||disposed||!owners.contains(owner)||pending!=null)throw IOException("Picker unavailable")
      val job=Job(owner,id,reply);pending=job;pickerOpen=true
      try{
       val intent=Intent(Intent.ACTION_OPEN_DOCUMENT).apply{
        addCategory(Intent.CATEGORY_OPENABLE);type="image/*"
        putExtra(Intent.EXTRA_ALLOW_MULTIPLE,true)
        putExtra(Intent.EXTRA_MIME_TYPES,arrayOf("image/png","image/jpeg","image/gif","image/webp","image/svg+xml"))
       }
       @Suppress("DEPRECATION")
       activity.startActivityForResult(intent,requestCode)
      }catch(_:Exception){pending=null;pickerOpen=false;throw IOException("Picker unavailable")}
     }
     "retireOwner"->{
      if(!owners.contains(owner)&&!retired.contains(owner)&&retired.size>=4096)throw IOException("Owner capacity reached")
      owners.remove(owner);retired.add(owner)
      pending?.takeIf{it.owner==owner}?.cancel()
      // Slot stays occupied until the original SAF result arrives. Wait only
      // actual bounded copy/cleanup, never the human system picker.
      worker.execute{
       try{
        cleanupOwner(owner)
        main.post{reply.success(mapOf("format" to 1,"owner" to owner,"retired" to true))}
       }catch(_:Exception){main.post{reply.error("image_retire_cleanup_failed","Image owner revoked; cleanup unconfirmed",null)}}
      }
     }
     "release"->{
      val id=call.argument<String>("id")?:throw IOException("Missing image")
      if(!ids.matches(id)||synchronized(files){files[id]}!=owner)throw IOException("Unowned image")
      worker.execute{
       try{
        val file=File(inbox(),"$id.image")
        deleteTracked(file)
        main.post{
         synchronized(files){files.remove(id)}
         reply.success(mapOf("format" to 1,"released" to id))
        }
       }catch(_:Exception){main.post{reply.error("image_release_failed","Cannot remove private image inbox",null)}}
      }
     }
     else->reply.notImplemented()
    }
   }catch(_:Exception){reply.error("image_picker_unavailable","Cannot use owned image picker",null)}
  }
 }
 private fun inbox():File{
  val root=File(activity.cacheDir.canonicalFile,"owned-image-inbox-v1")
  if(root.canonicalFile!=root.absoluteFile||(!root.isDirectory&&!root.mkdir()))throw IOException("Inbox unavailable")
  return root
 }
 private fun deleteTracked(file:File){
  synchronized(inboxLock){
   val path=file.toPath()
   if(file.canonicalFile!=file.absoluteFile||Files.isSymbolicLink(path))throw IOException("Inbox link refused")
   if(Files.exists(path,LinkOption.NOFOLLOW_LINKS)&&
      (!Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)||!file.delete()))throw IOException("Inbox cleanup failed")
   activePaths.remove(file.absolutePath);ownedPaths.remove(file.absolutePath)
  }
 }
 private fun sweepOrphans(){
  val root=inbox()
  synchronized(inboxLock){
   var count=0
   Files.newDirectoryStream(root.toPath()).use{entries->
    for(path in entries){
     if(++count>4096)throw IOException("Image inbox entry budget")
     val file=path.toFile()
     if(!file.name.matches(Regex("^[a-f0-9]{32}\\.(part|image)$"))||
        file.canonicalFile!=file.absoluteFile||Files.isSymbolicLink(path)||
        !Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS))throw IOException("Unknown inbox entry preserved")
     if(!activePaths.contains(file.absolutePath)&&!file.delete())throw IOException("Orphan cleanup failed")
    }
   }
  }
 }
 private fun cleanupOwner(owner:String){
  val owned=synchronized(inboxLock){ownedPaths.filterValues{it==owner}.keys.toList()}
  for(path in owned)deleteTracked(File(path))
  synchronized(files){files.entries.removeAll{it.value==owner}}
 }
 private fun name(uri:Uri,job:Job):String{
  var result="attachment"
  activity.contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE),null,null,null,job.signal)?.use{c->
   if(c.moveToFirst()){
    val size=c.getColumnIndex(OpenableColumns.SIZE)
    if(size>=0&&!c.isNull(size)&&c.getLong(size)>limit)throw IOException("Image exceeds64MiB")
    val index=c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
    if(index>=0)result=c.getString(index)?:"attachment"
   }
  }
  // Match attachmentName normalization without changing a legitimate extension.
  result=result.replace('\\','/').substringAfterLast('/').map{if(it.code<32||it.code==127)' 'else it}.joinToString("").trim()
  if(result.length>180)result=result.takeLast(180)
  // A suffix cut can start at the low half of an otherwise valid emoji.
  if(result.isNotEmpty()&&Character.isLowSurrogate(result.first()))result=result.drop(1)
  if(result.isNotEmpty()&&Character.isHighSurrogate(result.last()))result=result.dropLast(1)
  result=result.trim()
  var offset=0
  while(offset<result.length){
   val ch=result[offset]
   if(Character.isHighSurrogate(ch)){
    if(offset+1>=result.length||!Character.isLowSurrogate(result[offset+1]))throw IOException("Invalid Unicode image name")
    offset+=2
   }else{
    if(Character.isLowSurrogate(ch))throw IOException("Invalid Unicode image name")
    offset++
   }
  }
  return if(result.isEmpty()||result=="."||result=="..")"attachment"else result
 }
 fun onActivityResult(code:Int,resultCode:Int,data:Intent?):Boolean{
  if(code!=requestCode)return false
  pickerOpen=false
  val job=pending?:return true
  if(job.copying)return true
  if(resultCode!=Activity.RESULT_OK||job.cancelled||!owners.contains(job.owner)){
   pending=null;job.reply.success(mapOf("format" to 1,"cancelled" to true));return true
  }
  val uris=mutableListOf<Uri>()
  data?.clipData?.let{clip->if(clip.itemCount>20){pending=null;job.reply.error("image_selection_limit","Select at most20 images",null);return true}
   for(i in 0 until clip.itemCount)uris.add(clip.getItemAt(i).uri)}
  if(uris.isEmpty())data?.data?.let{uris.add(it)}
  if(uris.isEmpty()||uris.size>20||uris.distinct().size!=uris.size||uris.any{it.scheme!="content"}){
   pending=null;job.reply.error("image_provider_invalid","Select image documents",null);return true
  }
  job.copying=true
  val deadline=SystemClock.elapsedRealtime()+120_000
  val timeout=timer.schedule({job.cancel()},120,TimeUnit.SECONDS)
  worker.execute{
   val made=mutableListOf<File>()
   val receipts=mutableListOf<Map<String,Any>>()
   try{
    val root=inbox();var batch=0L
    fun check(){if(job.cancelled||disposed||SystemClock.elapsedRealtime()>=deadline||Thread.currentThread().isInterrupted)throw IOException("Image copy interrupted")}
    for((index,uri)in uris.withIndex()){
     check()
     val display=name(uri,job)
     val mime=activity.contentResolver.getType(uri)?:""
     if(mime !in setOf("image/png","image/jpeg","image/gif","image/webp","image/svg+xml"))throw IOException("Unsupported image MIME")
     val id=MessageDigest.getInstance("SHA-256").digest((job.id+"/"+index).toByteArray()).take(16).joinToString(""){"%02x".format(it.toInt()and 255)}
     val part=File(root,"$id.part");val target=File(root,"$id.image")
     synchronized(inboxLock){
      if(part.canonicalFile!=part.absoluteFile||target.canonicalFile!=target.absoluteFile||part.exists()||target.exists()||!part.createNewFile())throw IOException("Image identity collision")
      activePaths.add(part.absolutePath);ownedPaths[part.absolutePath]=job.owner
     }
     made.add(part)
     val digest=MessageDigest.getInstance("SHA-256");var total=0L
     val descriptor=activity.contentResolver.openAssetFileDescriptor(uri,"r",job.signal)?:throw IOException("Cannot open image")
     job.descriptor=descriptor
     val expected=descriptor.declaredLength
     descriptor.use{afd->
      check()
      if(expected>limit||expected>=0&&batch+expected>batchLimit)throw IOException("Image selection exceeds byte bound")
      afd.createInputStream().use{input->
       FileOutputStream(part).use{output->
        val poll=StructPollfd().apply{fd=(input as FileInputStream).fd;events=OsConstants.POLLIN.toShort()}
        val buffer=ByteArray(64*1024)
        while(true){
         check()
         if(StatFs(root.path).availableBytes<reserve+buffer.size)throw IOException("Insufficient space")
         poll.revents=0
         if(Os.poll(arrayOf(poll),1000)==0)continue
         val count=input.read(buffer);if(count<0)break;if(count==0)continue
         total+=count;batch+=count
         if(total>limit||batch>batchLimit)throw IOException("Image selection exceeds byte bound")
         digest.update(buffer,0,count);output.write(buffer,0,count)
        }
        output.flush();output.fd.sync()
       }
      }
     }
     job.descriptor=null;check()
     if(total<=0||expected>=0&&total!=expected)throw IOException("Incomplete image")
     synchronized(inboxLock){
      if(!part.renameTo(target))throw IOException("Image copy incomplete")
      activePaths.remove(part.absolutePath);ownedPaths.remove(part.absolutePath)
      activePaths.add(target.absolutePath);ownedPaths[target.absolutePath]=job.owner
     }
     made.remove(part);made.add(target)
     receipts.add(mapOf("id" to id,"name" to display,"mime" to mime,"bytes" to total,
      "sha256" to digest.digest().joinToString(""){"%02x".format(it.toInt()and 255)}))
    }
    // Track completed files before the main-thread delivery so a retirement
    // queued between copy completion and delivery still drains every file.
    for(r in receipts)synchronized(files){files[r["id"] as String]=job.owner}
    main.post{
     if(!disposed&&pending===job&&!job.cancelled&&owners.contains(job.owner)){
      pending=null;job.reply.success(mapOf("format" to 1,"cancelled" to false,"owner" to job.owner,"id" to job.id,"files" to receipts))
     }else{
      for(file in made)try{deleteTracked(file)}catch(_:Exception){}
      if(pending===job){pending=null;job.reply.error("image_import_interrupted","Image selection retired",null)}
     }
    }
   }catch(_:Exception){
    for(file in made)try{deleteTracked(file)}catch(_:Exception){}
    main.post{if(pending===job){pending=null;job.reply.error("image_import_failed","Cannot copy images: check size, space and provider",null)}}
   }finally{timeout.cancel(false);job.descriptor=null}
  }
  return true
 }
 fun onHostStopped(){if(!pickerOpen)pending?.cancel()}
 fun dispose(){
  disposed=true;channel.setMethodCallHandler(null);owners.clear();pending?.cancel()
  pending?.reply?.error("image_import_interrupted","Image picker destroyed",null);pending=null
  worker.execute{for(owner in synchronized(inboxLock){ownedPaths.values.toSet()})try{cleanupOwner(owner)}catch(_:Exception){}}
  worker.shutdown();timer.shutdownNow()
 }
}
