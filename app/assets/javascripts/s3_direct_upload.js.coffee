
#= require jquery-fileupload/basic
#= require jquery-fileupload/vendor/tmpl


$ = jQuery

$.fn.S3Uploader = (options) ->

  # support multiple elements
  if @length > 1
    @each ->
      $(this).S3Uploader options

    return this

  $uploadForm = this

  settings =
    path: ''
    additional_data: null
    before_add: null
    remove_completed_progress_bar: true
    remove_failed_progress_bar: false
    progress_bar_target: null
    click_submit_target: null
    allow_multiple_files: true

  $.extend settings, options

  current_files = []
  forms_for_submit = []
  if settings.click_submit_target
    settings.click_submit_target.click ->
      form.submit() for form in forms_for_submit
      false

  setUploadForm = ->
    ## image duplication in different sizes:
    $.blueimp.fileupload::processActions.duplicateImage = (data, options) ->
      if data.canvas
        data.files.push data.files[data.index]
      data

    $uploadForm.fileupload(
      previewMaxWidth: 236
      previewMaxHeight: 236
      # forceIframeTransport: false  ## default
      # singleFileUploads: true ## default
      # prependFiles: true # By default(false), files are appended to the files container. Set this option to true, to prepend files instead.
      # maxNumberOfFiles: 10   # Not working, probably this is indeed: # of data.files
      maxFileSize: 20000000
      imageForceResize: true
      imageQuality: 80
      imageMaxWidth: 1600  # 1600
      imageMaxHeight: 1600 # 1600
      # https://github.com/blueimp/jQuery-File-Upload/wiki/Options -> to see options (1-8),or (boolean)
      imageOrientation: true
      disableImageMetaDataSave: true #Otherwise orientation is broken on iOS Safari
      disableImageResize: true
      #previewOrientation: 0
      # imageCrop: false
      acceptFileTypes: /(\.|\/)(gif|jpe?g|png|webp|tiff|tif)$/i
      
      #### resize photos for S3 ... 
        # processQueue: [
        #   {
        #     action: 'loadImage'
        #     fileTypes: /^image\/(gif|jpeg|png)$/
        #     maxFileSize: 20000000
        #   }
        #   {
        #     action: 'resizeImage'
        #     maxWidth: 800
        #     maxHeight: 800
        #     # jpeg_quality: 100
        #   }
        #   { action: 'saveImage' }
        #   { action: 'duplicateImage' }
        #   {
        #     action: 'resizeImage'
        #     maxWidth: 400
        #     maxHeight: 400
        #     # jpeg_quality: 100
        #   }
        #   { action: 'saveImage' }
        #   { action: 'duplicateImage' }
        #   {
        #     action: 'resizeImage'
        #     maxWidth: 200
        #     maxHeight: 200
        #     # jpeg_quality: 100
        #     # crop: true
        #   }
        #   { action: 'saveImage' }
        # ]

      add: (e, data) -> # callback for the file upload request queue. It is invoked as soon as files are added 
        current_data = $(this)
        data.process(->
          return current_data.fileupload('process', data)
        ).done(->
          
          #### From this line below, I tried to send resized photos to S3 as well.. 
          #### Couldn't succeed to re-ignite. (lack of forms, lack of re-initiation during 1st process)
            # file1 = data.files[0]
            # file2 = data.files[1]
            # file3 = data.files[2]
            # # bu isimlendirmede hata oluyo, kucuk dosya gelince, olusturulmuyo o size'in altindakiler. 
            # # ++ small'mu, medium'mu onu da bilemeyiz aslinda. bu durumda. belki de medium'da oluyo. hepsi yani ayni dosya olmali. 
            # file1.unique_id = password
            # file2.unique_id = password
            # file3.unique_id = password
            # file1.name = file1.name.replace(/(\.[\w\d_-]+)$/i, '_small$1')
            # file2.name = file2.name.replace(/(\.[\w\d_-]+)$/i, '_large$1')
            # file3.name = file3.name.replace(/(\.[\w\d_-]+)$/i, '_medium$1');
            # # leave only 1 file in data.files.
            # data.files.splice(2,1)
            # data.files.splice(0,1)

          file = data.files[0]
          password = Math.random().toString(36).substr(2,16)
          file.unique_id = password
          #### abort button koyuyoruz.
          # abortBtn = $('<a/>').attr('href', 'javascript:void(0)').addClass('btn btn-default').append('Abort').click(->
          #   data.abort()
          #   data.context.remove()
          #   $(this).remove()
          #   return
          # )
          # data.context = $('<div/>').appendTo('#abort_container')
          # data.context.append abortBtn
          #### abort button koyuyoruz.
          unless settings.before_add and not settings.before_add(file)
            current_files.push data
            if $('#template-upload').length > 0
              data.context = $($.trim(tmpl("template-upload", file)))
              $(data.context).appendTo(settings.progress_bar_target || $uploadForm)
            else if !settings.allow_multiple_files
              data.context = settings.progress_bar_target
            if settings.click_submit_target
              if settings.allow_multiple_files
                forms_for_submit.push data
              else
                forms_for_submit = [data]
            else
              data.submit()
        )


      start: (e) ->  # Callback for uploads start
        $uploadForm.trigger("s3_uploads_start", [e])

      progress: (e, data) ->  #C allback for upload progress events.
        if data.context
          progress = parseInt(data.loaded / data.total * 100, 10)
          data.context.find('.bar').css('width', progress + '%')

      done: (e, data) -> #Callback for successful upload requests.
        # here you can perform an ajax call to get your documents to display on the screen.
        # $('#your_documents').load("/documents?for_item=1234");

        content = build_content_object $uploadForm, data.files[0], data.result

        callback_url = $uploadForm.data('callback-url')
        if callback_url
          content[$uploadForm.data('callback-param')] = content.url

          # S3'ten gelen cevap sonrasi db'ye yollamak icin bunu hazirliyoz.
          $.ajax
            type: $uploadForm.data('callback-method')
            url: callback_url
            data: content
            beforeSend: ( xhr, settings )       ->
              event = $.Event('ajax:beforeSend')
              $uploadForm.trigger(event, [xhr, settings])
              return event.result
            complete:   ( xhr, status )         ->
              event = $.Event('ajax:complete')
              $uploadForm.trigger(event, [xhr, status])
              return event.result
            success:    ( data, status, xhr )   ->
              event = $.Event('ajax:success')
              $uploadForm.trigger(event, [data, status, xhr])
              return event.result
            error:      ( xhr, status, error )  ->
              event = $.Event('ajax:error')
              $uploadForm.trigger(event, [xhr, status, error])
              return event.result

        data.context.remove() if data.context && settings.remove_completed_progress_bar # remove progress bar
        $uploadForm.trigger("s3_upload_complete", [content])

        current_files.splice($.inArray(data, current_files), 1) # remove that element from the array
        $uploadForm.trigger("s3_uploads_complete", [content]) unless current_files.length

      fail: (e, data) -> # Callback for failed (abort or error) upload requests
        content = build_content_object $uploadForm, data.files[0], data.result
        content.error_thrown = data.errorThrown

        data.context.remove() if data.context && settings.remove_failed_progress_bar # remove progress bar
        $uploadForm.trigger("s3_upload_failed", [content])

      #### CALLBACKS ####
      # submit: (e, data) ->  # Callback for the submit event of each file upload.
      # send: (e, data) ->    # Callback for the start of each file upload request.
      # always: (e, data) ->  # Callback for completed (success, abort or error) upload requests 
      # progressall: (e,data ) -> #Callback for global upload progress events.
      # stop: (e, data) ->    # Callback for uploads stop
      # change: (e, data) ->  # Callback for change events of the fileInput collection
      # paste: (e, data) ->   # Callback for paste events to the dropZone collection  
      # drop: (e, data) ->    # Callback for drop events of the dropZone collection
      # dragover: (e, data)-> #Callback for dragover events of the dropZone collection.

      formData: (form) ->
        data = form.serializeArray()
        fileType = ""
        if "type" of @files[0]
          fileType = @files[0].type
        data.push
          name: "content-type"
          value: fileType

        key = $uploadForm.data("key")
          .replace('{timestamp}', new Date().getTime())
          .replace('{unique_id}', @files[0].unique_id)
          .replace('{extension}', @files[0].name.split('.').pop())

        # substitute upload timestamp and unique_id into key
        key_field = $.grep data, (n) ->
          n if n.name == "key"

        if key_field.length > 0
          key_field[0].value = settings.path + key

        # IE <= 9 doesn't have XHR2 hence it can't use formData
        # replace 'key' field to submit form
        unless 'FormData' of window
          $uploadForm.find("input[name='key']").val(settings.path + key)
        data

      
      ).bind 'fileuploadprocessalways', (e, data) ->
        canvas = data.files[0].preview
        if canvas
          dataURL = canvas.toDataURL()
          $("#preview-image").removeClass('hidden').attr("src", dataURL)


  build_content_object = ($uploadForm, file, result) ->
    content = {}
    if result # Use the S3 response to set the URL to avoid character encodings bugs
      content.url            = $(result).find("Location").text()
      content.filepath       = $('<a />').attr('href', content.url)[0].pathname
    else # IE <= 9 retu      rn a null result object so we use the file object instead
      domain                 = $uploadForm.attr('action')
      content.filepath       = $uploadForm.find('input[name=key]').val().replace('/${filename}', '')
      content.url            = domain + content.filepath + '/' + encodeURIComponent(file.name)

    content.filename         = file.name
    content.filesize         = file.size if 'size' of file
    content.lastModifiedDate = file.lastModifiedDate if 'lastModifiedDate' of file
    content.filetype         = file.type if 'type' of file
    content.unique_id        = file.unique_id if 'unique_id' of file
    content.relativePath     = build_relativePath(file) if has_relativePath(file)
    content = $.extend content, settings.additional_data if settings.additional_data
    content

  has_relativePath = (file) ->
    file.relativePath || file.webkitRelativePath

  build_relativePath = (file) ->
    file.relativePath || (file.webkitRelativePath.split("/")[0..-2].join("/") + "/" if file.webkitRelativePath)

  #public methods
  @initialize = ->
    # Save key for IE9 Fix
    $uploadForm.data("key", $uploadForm.find("input[name='key']").val())

    setUploadForm()
    this

  @path = (new_path) ->
    settings.path = new_path

  @additional_data = (new_data) ->
    settings.additional_data = new_data

  @initialize()
