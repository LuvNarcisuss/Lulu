-- The selected Free plan permits a maximum global file size of 50 MB.
update storage.buckets set file_size_limit=52428800 where id in ('catalog','uploads');
