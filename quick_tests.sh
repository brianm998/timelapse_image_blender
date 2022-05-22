TEST_SEQUENCE=20_300_200
TEST_DIR=/op/test

rm -f $TEST_DIR/$TEST_SEQUENCE*.mov
./timelapse_image_blender.pl linear --size=2 --sequence=$TEST_DIR/LRT_$TEST_SEQUENCE && \
./timelapse_image_blender.pl bell-curve --size=3 --max=2 --min=1 --sequence=$TEST_DIR/LRT_$TEST_SEQUENCE && \
./timelapse_image_blender.pl smooth-ramp  --size=3 --max=2 --min=1 --sequence=$TEST_DIR/LRT_$TEST_SEQUENCE && \
./timelapse_image_blender.pl streak --start=3 --mid=8 --end=12 --size=4 --sequence=$TEST_DIR/LRT_$TEST_SEQUENCE
ls $TEST_DIR/$TEST_SEQUENCE*.mov | wc -l
