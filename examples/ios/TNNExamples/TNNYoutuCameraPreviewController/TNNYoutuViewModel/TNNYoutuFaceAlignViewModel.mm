// Tencent is pleased to support the open source community by making TNN available.
//
// Copyright (C) 2020 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the BSD 3-Clause License (the "License"); you may not use this file except
// in compliance with the License. You may obtain a copy of the License at
//
// https://opensource.org/licenses/BSD-3-Clause
//
// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

#import "TNNYoutuFaceAlignViewModel.h"
#import "YoutuFaceAlign.h"
#import "BlazeFaceDetector.h"
#import "UIImage+Utility.h"

#import <Metal/Metal.h>
#import <memory>

using namespace std;

#define PROFILE 0

@implementation TNNYoutuFaceAlignViewModel

- (std::shared_ptr<BlazeFaceDetector>) loadFaceDetector:(TNNComputeUnits)units {
    std::shared_ptr<BlazeFaceDetector> predictor = nullptr;
    
    auto library_path = [[NSBundle mainBundle] pathForResource:@"tnn.metallib" ofType:nil];
    auto model_path = [[NSBundle mainBundle] pathForResource:@"model/blazeface/blazeface.tnnmodel"
                                                      ofType:nil];
    auto proto_path = [[NSBundle mainBundle] pathForResource:@"model/blazeface/blazeface.tnnproto"
                                                      ofType:nil];
    if (proto_path.length <= 0 || model_path.length <= 0) {
        NSLog(@"Error: proto or model path is invalid");
        return predictor;
    }
    
    string proto_content =
    [NSString stringWithContentsOfFile:proto_path encoding:NSUTF8StringEncoding error:nil].UTF8String;
    NSData *data_mode    = [NSData dataWithContentsOfFile:model_path];
    string model_content = [data_mode length] > 0 ? string((const char *)[data_mode bytes], [data_mode length]) : "";
    if (proto_content.size() <= 0 || model_content.size() <= 0) {
        NSLog(@"Error: proto or model path is invalid");
        return predictor;
    }
    //blazeface requires input with shape 128*128
    const int target_height = 128;
    const int target_width  = 128;
    DimsVector target_dims  = {1, 3, target_height, target_width};
    
    auto option = std::make_shared<BlazeFaceDetectorOption>();
    {
        option->proto_content = proto_content;
        option->model_content = model_content;
        option->library_path = library_path.UTF8String;
        option->compute_units = units;
        
        option->input_width = target_width;
        option->input_height = target_height;
        //min_score_thresh
        option->min_score_threshold = 0.75;
        //min_suppression_thresh
        option->min_suppression_threshold = 0.3;
        //predefined anchor file path
        option->anchor_path = string([[[NSBundle mainBundle] pathForResource:@"blazeface_anchors.txt" ofType:nil] UTF8String]);
    }
    
    predictor = std::make_shared<BlazeFaceDetector>();
    auto status = predictor->Init(option);
    if (status != TNN_OK) {
        NSLog(@"Error: %s", status.description().c_str());
        return nullptr;
    }
    
    return predictor;
}

- (std::shared_ptr<YoutuFaceAlign>) loadYoutuFaceAlign:(TNNComputeUnits)units : (int) phase {
    std::shared_ptr<YoutuFaceAlign> predictor = nullptr;
    
    auto library_path = [[NSBundle mainBundle] pathForResource:@"tnn.metallib" ofType:nil];
    NSString *model_path = nil;
    NSString *proto_path = nil;
    
    if(1 == phase) {
        model_path = [[NSBundle mainBundle] pathForResource:@"model/youtu_facealign/p1_bf16_easy.opt.tnnmodel"
                                                     ofType:nil];
        proto_path = [[NSBundle mainBundle] pathForResource:@"model/youtu_facealign/p1_bf16_easy_remove_vis_addsigmoid.opt.tnnproto"
                                                     ofType:nil];
    } else if(2 == phase) {
        model_path = [[NSBundle mainBundle] pathForResource:@"model/youtu_facealign/p2_bf16_easy.opt.tnnmodel"
                                                     ofType:nil];
        proto_path = [[NSBundle mainBundle] pathForResource:@"model/youtu_facealign/p2_bf16_easy_remove_vis.opt.tnnproto"
                                                     ofType:nil];
    } else{
        NSLog(@"Error: facealign model phase is invalid");
        return nullptr;
    }
    
    if (proto_path.length <= 0 || model_path.length <= 0) {
        NSLog(@"Error: proto or model path is invalid");
        return predictor;
    }
    
    string proto_content =
    [NSString stringWithContentsOfFile:proto_path encoding:NSUTF8StringEncoding error:nil].UTF8String;
    NSData *data_mode    = [NSData dataWithContentsOfFile:model_path];
    string model_content = [data_mode length] > 0 ? string((const char *)[data_mode bytes], [data_mode length]) : "";
    if (proto_content.size() <= 0 || model_content.size() <= 0) {
        NSLog(@"Error: proto or model path is invalid");
        return predictor;
    }
    //youtu facealign models require input with shape 128*128
    const int target_height = 128;
    const int target_width  = 128;
    DimsVector target_dims  = {1, 1, target_height, target_width};
    
    auto option = std::make_shared<YoutuFaceAlignOption>();
    {
        option->proto_content = proto_content;
        option->model_content = model_content;
        option->library_path = library_path.UTF8String;
        option->compute_units = units;
        
        option->input_width = target_width;
        option->input_height = target_height;
        //face threshold
        option->face_threshold = 0.5;
        option->min_face_size = 20;
        //model phase
        option->phase = phase;
        //net_scale
        option->net_scale = phase == 1? 1.2 : 1.3;
        //mean pts path
        string mean_file_path = string([[[NSBundle mainBundle] pathForResource: phase==1? @"mean_pts_phase1.txt" : @"mean_pts_phase2.txt" ofType:nil] UTF8String]);
        option->mean_pts_path = std::move(mean_file_path);
    }
    
    predictor = std::make_shared<YoutuFaceAlign>();
    auto status = predictor->Init(option);
    if (status != TNN_OK) {
        NSLog(@"Error: %s", status.description().c_str());
        return nullptr;
    }
    
    return predictor;
}

-(Status)loadNeuralNetworkModel:(TNNComputeUnits)units {
    Status status = TNN_OK;
    auto face_detector = [self loadFaceDetector:units];
    auto predictor_phase1 = [self loadYoutuFaceAlign:units :1];
    auto predictor_phase2 = [self loadYoutuFaceAlign:units :2];
    
    self.predictor = face_detector;
    self.predictor_phase1 = predictor_phase1;
    self.predictor_phase2 = predictor_phase2;
    //TODO: we need to set it to false when change camera
    self.prev_face = false;
    
    return status;
}

-(Status)Run:(std::shared_ptr<char>)image_data
             height:(int) height
             width :(int) width
             output:(std::shared_ptr<TNNSDKOutput>&) sdk_output
            counter:(std::shared_ptr<TNNFPSCounter>) counter {
    Status status = TNN_OK;
    
    //for muti-thread safety, increase ref count, to insure predictor is not released while detecting object
    auto face_detector_async_thread = self.predictor;
    auto align_phase1_async_thread = self.predictor_phase1;
    auto align_phase2_async_thread = self.predictor_phase2;
    auto units = self.predictor->GetComputeUnits();
    
    const int image_orig_height = height;
    const int image_orig_width  = width;
    TNN_NS::DimsVector orig_image_dims = {1, 3, image_orig_height, image_orig_width};

    counter->Begin("Copy");
    // mat for the input image
    shared_ptr<TNN_NS::Mat> image_mat = nullptr;
    // construct image_mat
    if (units == TNNComputeUnitsGPU) {
        image_mat = std::make_shared<TNN_NS::Mat>(DEVICE_METAL, TNN_NS::N8UC4, orig_image_dims);

        id<MTLTexture> texture_rgba = (__bridge id<MTLTexture>)image_mat->GetData();
        if (!texture_rgba) {
            status = Status(TNNERR_NO_RESULT, "Error texture input rgba is nil");
            return status;
        }
        [texture_rgba replaceRegion:MTLRegionMake2D(0, 0, orig_image_dims[3], orig_image_dims[2])
                        mipmapLevel:0
                          withBytes:image_data.get()
                        bytesPerRow:orig_image_dims[3] * 4];
    } else if (units == TNNComputeUnitsCPU) {
        image_mat = std::make_shared<TNN_NS::Mat>(DEVICE_ARM, TNN_NS::N8UC4, orig_image_dims, image_data.get());
    }
    counter->End("Copy");

    // output of each model
    std::shared_ptr<TNNSDKOutput> sdk_output_face = nullptr;
    std::shared_ptr<TNNSDKOutput> sdk_output1 = nullptr;
    std::shared_ptr<TNNSDKOutput> sdk_output2 = nullptr;
    
    std::shared_ptr<TNN_NS::Mat> phase1_pts = nullptr;
    
    counter->Begin("Phase1");
    //phase1 model
    {
        // 1) prepare input for phase1 model
        if(!self.prev_face) {
            // i) get face from detector
            auto facedetector_input_dims = face_detector_async_thread->GetInputShape();
            
            //preprocess
            auto input_mat = std::make_shared<TNN_NS::Mat>(image_mat->GetDeviceType(), TNN_NS::N8UC4, facedetector_input_dims);
#if PROFILE
            Timer timer;
            const std::string tag = (units == TNNComputeUnitsCPU)? "CPU": "GPU";
            timer.start();
            face_detector_async_thread->Resize(image_mat, input_mat, TNNInterpLinear);
            timer.printElapsed(tag, "FaceAlign Detector Resize");
#else
            face_detector_async_thread->Resize(image_mat, input_mat, TNNInterpLinear);
#endif
            status = face_detector_async_thread->Predict(std::make_shared<BlazeFaceDetectorInput>(input_mat), sdk_output_face);
            RETURN_ON_NEQ(status, TNN_OK);
            
            std::vector<BlazeFaceInfo> face_info;
            if (sdk_output_face && dynamic_cast<BlazeFaceDetectorOutput *>(sdk_output_face.get()))
            {
                auto face_output = dynamic_cast<BlazeFaceDetectorOutput *>(sdk_output_face.get());
                face_info = face_output->face_list;
            }
            if(face_info.size() <= 0) {
                //no faces, return
                LOGD("Error no faces found!\n");
                return status;
            }
            auto face = face_info[0];
            // scale the face point according to the original image size
            auto face_orig = face.AdjustToViewSize(image_orig_height, image_orig_width, 2);
            //LOGE("face_origin:(%f,%f,%f,%f), conf=%.4f\n", face_orig.x1, face_orig.y1, face_orig.x2, face_orig.y2, face_orig.score);
            
            // set face region for phase1 model
            if(!align_phase1_async_thread->SetFaceRegion(face_orig.x1, face_orig.y1, face_orig.x2, face_orig.y2)) {
                //no invalid faces, return
                LOGD("Error no valid faces found!\n");
                return status;
            }
        }
        
        // 2) predict
        status = align_phase1_async_thread->Predict(std::make_shared<YoutuFaceAlignInput>(image_mat), sdk_output1);
        RETURN_ON_NEQ(status, TNN_OK);
        
        // update prev_face
        self.prev_face = align_phase1_async_thread->GetPrevFace();
        if(!self.prev_face) {
            LOGE("Next frame will use face detector!\n");
        }
        phase1_pts = align_phase1_async_thread->GetPrePts();
    }
    counter->End("Phase1");

    counter->Begin("Phase2");
    std::shared_ptr<TNN_NS::Mat> phase2_pts = nullptr;
    //phase2 model
    {
        // 1) prepare phase1 pts
        align_phase2_async_thread->SetPrePts(phase1_pts, true);
        // 2) predict
        status = align_phase2_async_thread->Predict(std::make_shared<YoutuFaceAlignInput>(image_mat), sdk_output2);
        RETURN_ON_NEQ(status, TNN_OK);
        phase2_pts = align_phase2_async_thread->GetPrePts();
    }
    counter->End("Phase2");

    {
        sdk_output = std::make_shared<YoutuFaceAlignOutput>();
        auto phase1_output = dynamic_cast<YoutuFaceAlignOutput *>(sdk_output1.get());
        auto phase2_output = dynamic_cast<YoutuFaceAlignOutput *>(sdk_output2.get());

        auto& points        = phase1_output->face.key_points;
        auto& points_phase2 = phase2_output->face.key_points;

        points.insert(points.end(), points_phase2.begin(), points_phase2.end());

        auto output = dynamic_cast<YoutuFaceAlignOutput *>(sdk_output.get());
        output->face.key_points = points;
        output->face.image_height = image_orig_height;
        output->face.image_width  = image_orig_width;
    }
    return status;
}

-(YoutuFaceAlignInfo)getFace:(std::shared_ptr<TNNSDKOutput>)sdk_output {
    YoutuFaceAlignInfo face;
    if (sdk_output && dynamic_cast<YoutuFaceAlignOutput *>(sdk_output.get())) {
        auto face_output = dynamic_cast<YoutuFaceAlignOutput *>(sdk_output.get());
        face = face_output->face;
    }
    return face;
}

@end
