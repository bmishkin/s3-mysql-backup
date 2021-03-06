require 'aws/s3'

# wrapper for S3 operations
#
class S3Utils

  def initialize(access_key_id, secret_access_key, bucket)
    @bucket = bucket
    connect(access_key_id, secret_access_key)
    ensure_bucket_exists
    self
  end

  # def copy(from, to)
  #   AWS::S3::S3Object.copy(File.basename(from), File.basename(to), @bucket)
  # end

  def store(file_path)
    obj = @s3_bucket.objects[File.basename(file_path)]
    obj.write(Pathname.new(file_path))
    # AWS::S3::S3Object.store(File.basename(file_path), open(file_path), @bucket)
  end

  def delete(file_path)
    obj = @s3_bucket.objects[File.basename(file_path)]
    obj.delete
    # AWS::S3::S3Object.delete(File.basename(file_path), @bucket)
  end

  # def list
  #   AWS::S3::Bucket.find(@bucket).objects.each do |obj|
  #     puts "#{obj.bucket.name}/#{obj.key}"
  #   end
  # end

  protected

  def connect(access_key_id, secret_access_key)
    # AWS::S3::Base.establish_connection!(
    @s3 = AWS::S3.new(
      :access_key_id     => access_key_id,
      :secret_access_key => secret_access_key
    )
  end

  def ensure_bucket_exists
    #AWS::S3::Bucket.find(@bucket)
    @s3_bucket = @s3.buckets[@bucket]
    rescue AWS::S3::NoSuchBucket
    #AWS::S3::Bucket.create(@bucket)
    @s3_the_bucket = @s3.buckets.create[@bucket]
  end

end
