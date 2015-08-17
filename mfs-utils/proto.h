/* This file is automatically generated with "make proto". DO NOT EDIT */
typedef union _tar_record tar_record;

unsigned fsid_hash(unsigned fsid, unsigned size);
int inode_count() ;
void dump_sectors(void *d, int n);
int mfs_valid_fsid(int fsid);
void mfs_load_inode(int fsid, struct mfs_inode *inode);
void mfs_store_inode(int fsid, struct mfs_inode *inode);
void mfs_init_dev_fix(char *dev, int fix);
void mfs_init_dev(char *dev) ;
void mfs_init_fix(int fix);
void mfs_init() ;
void mfs_info(void);
void mfs_fsid_info(int fsid);
u32 mfs_fsid_pread(int fsid, void *buf, u64 ofs, u32 count);
u32 mfs_fsid_pwrite(int fsid, void *buf, u64 ofs, u32 count);
int mfs_fsid_type(int fsid);
u64 mfs_fsid_size(int fsid);
struct mfs_dirent *mfs_dir(int fsid, u32 *count);
void mfs_dir_free(struct mfs_dirent *dir);
char *mfs_type_string(int type);
u32 mfs_resolve(const char *pathin);
void mfs_all_inodes(void (*fn)(struct mfs_inode *));
struct bitmap *mfs_zone_bitmap(int zone, u64 limit);
void mfs_purge_zone(int zone, u32 limit);
void mfs_purge_all(u64 limit);
u32 mfs_zone_size(int zone);
void parse_object(int fsid, void *buf, object_fn fn);
char *object_typestr(int objtype);
void read_all(int fd, void *buf, int size);
void write_all(int fd, void *buf, int size);
int open_socket_out(char *host, int port);
void byte_swap(void *p, char *desc);
u64 ll_seek(int fd, u64 offset, int whence);
u32 read_sectors(int fd, void *buf, u32 sector, u32 count);
u32 write_sectors(int fd, void *buf, u32 sector, u32 count);
void set_nonblocking(int fd);
int bitcount32(u32 x);
struct bitmap *bitmap_allocate(int n);
void bitmap_set(struct bitmap *bm, unsigned i, unsigned n);
int bitmap_query(struct bitmap *bm, unsigned i);
void mfs_readahead(int set);
void mfs_read_sectors(void *buf, u32 sec, u32 count);
run_desc mfs_list_sectors(u32 sec, u32 count);
void mfs_write_sectors(void *buf, u32 sec, u32 count);
void mfs_zero_sectors(int sector, int count);
u32 num_devs();
u32	dev_start_sector(u32 dev_no);
void load_devs(char *devlist, char *xlist[], int nxlist, int mode);
void add_dev_map(char *mapping);
void io_dev_info(void);
int io_vserver(void);
void io_need_bswap(int set);
u32 io_total_size(void);
void mfs_read_partial(void *buf, u32 sec, u64 size);
void mfs_write_partial(void *buf, u32 sec, u64 size);
int io_get_need_bswap(void);
void partition_parse(int fd);
u32 partition_remap(u32 sec);
u32 partition_total_size(void);
void clear_use_ptable();
u32 crc32(const unsigned char *bytes,int length);
int check_crc(void *buf, int length, u32 *crc);
int replace_crc(void *buf, int length, u32 *crc);
void auto_crc(void *buf, int max_length, u32 *crc);
int fixPriority( int pri );
int fixPriority(int pri);
int export_file(const u32 fsid, const int fd, u64 start, 
		 u64 count, int delayms, u32 nbufs, int verbose );
int list_sectors_for_file(const u32 fsid,  run_desc runs[], int maxruns );
const char *schema_type(int type);
const char *schema_attrib(int type, int attr);
void dump_schema(FILE *f);
void *query_part(int fsid, int subobj, const char *name, int *len);
char *query_string(int fsid, char *path);
int query_int(int fsid, char *path);
int query_int_list(int fsid, char *path, int ret[], int max);
struct mfs_obj_attr *query_object(int fsid, const char *path, int *count);
void query_streams(const char *path);
int tzoffset() ;
void create_tarheader(tar_record *rec, char *name, int size);
void write_tar_padding(int output_fd, int size);
void credits(void);
char *read_xml();
char *generate_xml(char *path);
int *get_parts() ;
int generate_NowShowing( int fd ) ;
void setup_syslog (int level);
